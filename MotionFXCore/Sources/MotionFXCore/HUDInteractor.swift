import CoreGraphics
import Foundation

/// 空中に浮かぶホログラムパネル。
public struct HUDPanel: Equatable, Sendable {
    public var center: CGPoint
    public var scale: CGFloat

    public init(center: CGPoint, scale: CGFloat) {
        self.center = center
        self.scale = scale
    }
}

public enum HUDPhase: Equatable, Sendable {
    /// パネルなし。
    case hidden
    /// パネルが出ていて、誰も触っていない。
    case idle
    /// 片手でつまんで移動中。
    case grabbed
    /// 両手でつまんで拡大・縮小中。
    case scaling
}

public struct HUDState: Equatable, Sendable {
    public var panel: HUDPanel?
    public var phase: HUDPhase
    public var hands: [TrackedHand]
    /// パネルが出るまでの進み具合（0...1）。手の ID ごと。パネルが出ていない間だけ入る。
    /// 消した直後の待ち時間も織り込んであるので、1 になった時点で必ずパネルが出る。
    public var summonProgress: [Int: Double]

    public init(
        panel: HUDPanel? = nil,
        phase: HUDPhase = .hidden,
        hands: [TrackedHand] = [],
        summonProgress: [Int: Double] = [:]
    ) {
        self.panel = panel
        self.phase = phase
        self.hands = hands
        self.summonProgress = summonProgress
    }
}

/// 手の姿勢の列を受け取り、パネルの出現・移動・拡縮・消去を決める状態機械。
///
/// - 手のひらを開いて静止 → パネルが出る
/// - パネルをつまむ → 掴む。つまんだまま動かす → 移動
/// - 両手でつまんで広げる・縮める → 拡大・縮小
/// - 手を横に払う → 消す
public struct HUDInteractor: Sendable {
    private enum Mode: Sendable {
        case hidden(cooldownUntil: TimeInterval)
        case idle
        case grabbed(hand: Int, offset: CGVector)
        case scaling(first: Int, second: Int, startDistance: CGFloat, startScale: CGFloat, offset: CGVector)
    }

    public let config: GestureConfig
    /// 指定するとパネルの中心をこの範囲内に留める。
    public var bounds: CGRect?

    private var tracker: HandTracker
    private var mode = Mode.hidden(cooldownUntil: 0)
    private var panel: HUDPanel?

    public init(config: GestureConfig = GestureConfig()) {
        self.config = config
        self.tracker = HandTracker(config: config)
    }

    public mutating func reset() {
        tracker.reset()
        mode = .hidden(cooldownUntil: 0)
        panel = nil
    }

    public mutating func update(hands poses: [HandPose], at time: TimeInterval) -> HUDState {
        let hands = tracker.update(hands: poses, at: time)
        let pinching = hands.filter(\.isPinching)
        var summonProgress: [Int: Double] = [:]

        switch mode {
        case .hidden(let cooldownUntil):
            // クールダウン中の静止は数えない。明けてから改めて summonHold だけ止める必要がある。
            // そうしないと、払って消した手を止めているだけで明けた瞬間に出し直してしまう。
            for hand in hands where hand.stillOpenDuration > 0 {
                let counted = min(hand.stillOpenDuration, time - cooldownUntil)
                summonProgress[hand.id] = min(max(counted / config.summonHold, 0), 1)
            }
            if let hand = hands.first(where: { summonProgress[$0.id] == 1 }) {
                let palm = hand.pose.palmCenter
                let center = CGPoint(x: palm.x, y: palm.y - config.summonOffset * hand.pose.handSize)
                panel = HUDPanel(center: clamped(center), scale: 1)
                mode = .idle
                summonProgress = [:]
            }

        case .idle:
            guard let current = panel else {
                mode = .hidden(cooldownUntil: time)
                break
            }
            let area = grabArea(of: current)
            if let hand = pinching.first(where: { area.contains($0.pose.pinchPoint) }) {
                // 少なくとも片手がパネルをつまんでいるときだけ操作を始める。
                if let other = scalePartner(for: hand, among: pinching, panel: current) {
                    beginScaling(hand, other, panel: current)
                } else {
                    beginGrab(hand, panel: current)
                }
            } else if hands.contains(where: { $0.swipe != nil && isSwipe(of: $0, across: current) }) {
                panel = nil
                mode = .hidden(cooldownUntil: time + config.dismissCooldown)
            }

        case .grabbed(let handID, let offset):
            guard let current = panel else {
                mode = .hidden(cooldownUntil: time)
                break
            }
            if let hand = hands.first(where: { $0.id == handID }) {
                if !hand.isPinching {
                    mode = .idle
                } else if let other = scalePartner(for: hand, among: pinching, panel: current) {
                    beginScaling(hand, other, panel: current)
                } else {
                    let center = clamped(hand.pose.pinchPoint + offset)
                    panel?.center = center
                }
            } else if !tracker.isTracking(handID) {
                mode = .idle
            }
            // 検出が一瞬途切れただけなら、掴んだまま待つ。

        case .scaling(let firstID, let secondID, let startDistance, let startScale, let offset):
            guard let current = panel else {
                mode = .hidden(cooldownUntil: time)
                break
            }
            let first = hands.first { $0.id == firstID }
            let second = hands.first { $0.id == secondID }
            let firstEnded = first.map { !$0.isPinching } ?? !tracker.isTracking(firstID)
            let secondEnded = second.map { !$0.isPinching } ?? !tracker.isTracking(secondID)

            if firstEnded || secondEnded {
                if let remaining = [first, second].compactMap({ $0 }).first(where: \.isPinching) {
                    beginGrab(remaining, panel: current)
                } else {
                    mode = .idle
                }
            } else if let first, let second {
                let a = first.pose.pinchPoint
                let b = second.pose.pinchPoint
                let distance = a.distance(to: b)
                let unclamped = startScale * distance / startDistance
                let scale = min(max(unclamped, config.minScale), config.maxScale)
                panel?.scale = scale
                if scale != unclamped {
                    // 上限・下限に当たったら、いまの手の間隔を基準に取り直す。
                    // そうしないと、行き過ぎたぶんを戻すまで逆方向に反応しなくなる。
                    mode = .scaling(
                        first: firstID,
                        second: secondID,
                        startDistance: max(distance, 1),
                        startScale: scale,
                        offset: offset
                    )
                }
                let center = clamped(a.midpoint(to: b) + offset)
                panel?.center = center
            }
        }

        return HUDState(panel: panel, phase: phase, hands: hands, summonProgress: summonProgress)
    }

    private var phase: HUDPhase {
        switch mode {
        case .hidden: .hidden
        case .idle: .idle
        case .grabbed: .grabbed
        case .scaling: .scaling
        }
    }

    private mutating func beginGrab(_ hand: TrackedHand, panel: HUDPanel) {
        mode = .grabbed(hand: hand.id, offset: panel.center - hand.pose.pinchPoint)
    }

    private mutating func beginScaling(_ first: TrackedHand, _ second: TrackedHand, panel: HUDPanel) {
        let a = first.pose.pinchPoint
        let b = second.pose.pinchPoint
        mode = .scaling(
            first: first.id,
            second: second.id,
            startDistance: max(a.distance(to: b), 1),
            startScale: panel.scale,
            offset: panel.center - a.midpoint(to: b)
        )
    }

    /// 拡大縮小に加わる 2 本目の手。パネルの近くをつまんでいる手に限る。
    /// 画面の隅でたまたまつまむ形になった手や、写り込んだ他人の手で拡縮が始まらないようにする。
    private func scalePartner(for hand: TrackedHand, among pinching: [TrackedHand], panel: HUDPanel) -> TrackedHand? {
        let area = grabArea(of: panel).insetBy(dx: -config.scaleReach, dy: -config.scaleReach)
        return pinching.first { $0.id != hand.id && area.contains($0.pose.pinchPoint) }
    }

    /// 払う動きがパネルの高さを通っているか。離れた場所での手の動きでは消さない。
    private func isSwipe(of hand: TrackedHand, across panel: HUDPanel) -> Bool {
        let reach = grabArea(of: panel).height / 2 + hand.pose.handSize
        return abs(hand.pose.palmCenter.y - panel.center.y) <= reach
    }

    private func grabArea(of panel: HUDPanel) -> CGRect {
        let width = config.panelBaseSize.width * panel.scale
        let height = config.panelBaseSize.height * panel.scale
        return CGRect(x: panel.center.x - width / 2, y: panel.center.y - height / 2, width: width, height: height)
            .insetBy(dx: -config.grabMargin, dy: -config.grabMargin)
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        guard let bounds else { return point }
        return CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }
}

private func - (lhs: CGPoint, rhs: CGPoint) -> CGVector {
    CGVector(dx: lhs.x - rhs.x, dy: lhs.y - rhs.y)
}

private func + (lhs: CGPoint, rhs: CGVector) -> CGPoint {
    CGPoint(x: lhs.x + rhs.dx, y: lhs.y + rhs.dy)
}
