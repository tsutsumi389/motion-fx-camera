import CoreGraphics

/// 手の関節。Vision の手指ポーズ検出が返す 21 点に対応する。
public enum HandJoint: String, CaseIterable, Sendable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip
}

/// 1 フレームぶんの手の姿勢。座標は画面座標（左上原点、ポイント単位）。
///
/// しきい値はすべて `handSize` に対する比率で判定するので、
/// カメラからの距離や画面サイズに依存しない。
public struct HandPose: Equatable, Sendable {
    /// 手の大きさとピンチの判定に必須の関節。欠けている検出結果は `HandPose` にできない。
    ///
    /// つまんでいる間は薬指や小指が他の指に隠れて検出されないことが多いので、
    /// それらは必須にしない（欠けていても掴んだ状態を維持できるようにする）。
    public static let requiredJoints: Set<HandJoint> = [.wrist, .thumbTip, .indexTip, .middleMCP]

    /// 描画用の骨格。各配列は手首から指先へ向かう関節の並び。
    public static let skeleton: [[HandJoint]] = [
        [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip],
        [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
        [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip],
        [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip],
        [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip],
    ]

    public let joints: [HandJoint: CGPoint]

    public init?(joints: [HandJoint: CGPoint]) {
        guard Self.requiredJoints.allSatisfy({ joints[$0] != nil }) else { return nil }
        self.joints = joints
    }

    /// 必須関節がそろっていることを呼び出し側が保証する場合のみ使う。
    init(uncheckedJoints joints: [HandJoint: CGPoint]) {
        self.joints = joints
    }

    public subscript(joint: HandJoint) -> CGPoint? { joints[joint] }

    /// 必須関節専用。`init` で存在を保証している。
    private func point(_ joint: HandJoint) -> CGPoint {
        joints[joint] ?? .zero
    }

    public var wrist: CGPoint { point(.wrist) }

    /// 手首から中指の付け根までの距離。各しきい値の基準長。
    public var handSize: CGFloat {
        max(wrist.distance(to: point(.middleMCP)), 1)
    }

    /// 親指と人差し指の先端の中点。ピンチ操作の作用点。
    public var pinchPoint: CGPoint {
        point(.thumbTip).midpoint(to: point(.indexTip))
    }

    /// 親指と人差し指の先端の距離（`handSize` 比）。小さいほどつまんでいる。
    public var pinchRatio: CGFloat {
        point(.thumbTip).distance(to: point(.indexTip)) / handSize
    }

    /// 手のひらの中心。必ず検出されている手首と中指の付け根だけから求める。
    /// 見えている関節の平均にすると、付け根の関節が検出に出入りするたびに位置が飛ぶ。
    public var palmCenter: CGPoint {
        let knuckle = point(.middleMCP)
        return CGPoint(
            x: wrist.x + (knuckle.x - wrist.x) * 0.6,
            y: wrist.y + (knuckle.y - wrist.y) * 0.6
        )
    }

    /// 人差し指〜小指がすべて伸びているか。
    /// 指先が第二関節より `ratio` 倍以上手首から遠ければ「伸びている」とみなす。
    /// 判定に必要な関節が欠けている指は「伸びていない」として扱う。
    public func areFingersExtended(ratio: CGFloat) -> Bool {
        let fingers: [(tip: HandJoint, pip: HandJoint)] = [
            (.indexTip, .indexPIP),
            (.middleTip, .middlePIP),
            (.ringTip, .ringPIP),
            (.littleTip, .littlePIP),
        ]
        return fingers.allSatisfy { finger in
            guard let tip = joints[finger.tip], let pip = joints[finger.pip] else { return false }
            return wrist.distance(to: tip) > wrist.distance(to: pip) * ratio
        }
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(other.x - x, other.y - y)
    }

    func midpoint(to other: CGPoint) -> CGPoint {
        CGPoint(x: (x + other.x) / 2, y: (y + other.y) / 2)
    }
}
