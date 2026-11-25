import MotionFXCore
import SwiftUI

enum HoloStyle {
    static let color = Color(red: 0.36, green: 0.88, blue: 1.0)
    static let accent = Color(red: 1.0, green: 0.72, blue: 0.3)
}

/// カメラ映像の上に重ねる HUD 全体。手の骨格とホログラムパネルを描く。
struct HUDOverlayView: View {
    let state: HUDState
    let config: GestureConfig

    var body: some View {
        ZStack {
            HandsLayer(
                hands: state.hands,
                summonHold: state.phase == .hidden ? config.summonHold : nil
            )

            if let panel = state.panel {
                HoloPanelView(phase: state.phase, scale: panel.scale)
                    .frame(width: config.panelBaseSize.width, height: config.panelBaseSize.height)
                    .scaleEffect(panel.scale)
                    .position(panel.center)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: state.panel != nil)
        .allowsHitTesting(false)
    }
}

/// 検出した手の骨格、つまみ位置のカーソル、パネルが出るまでの進捗リング。
private struct HandsLayer: View {
    let hands: [TrackedHand]
    /// nil 以外なら、手のひらの周りに「出るまでの進捗」を描く。
    let summonHold: TimeInterval?

    var body: some View {
        Canvas { context, _ in
            for hand in hands {
                drawSkeleton(of: hand, in: &context)
                drawCursor(of: hand, in: &context)
                if let summonHold, hand.stillOpenDuration > 0 {
                    drawSummonProgress(of: hand, hold: summonHold, in: &context)
                }
            }
        }
        .shadow(color: HoloStyle.color.opacity(0.9), radius: 5)
    }

    private func drawSkeleton(of hand: TrackedHand, in context: inout GraphicsContext) {
        for chain in HandPose.skeleton {
            let points = chain.compactMap { hand.pose[$0] }
            guard points.count > 1 else { continue }
            var path = Path()
            path.addLines(points)
            context.stroke(path, with: .color(HoloStyle.color.opacity(0.65)), lineWidth: 1.5)
        }
        for point in hand.pose.joints.values {
            let dot = CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)
            context.fill(Path(ellipseIn: dot), with: .color(HoloStyle.color))
        }
    }

    private func drawCursor(of hand: TrackedHand, in context: inout GraphicsContext) {
        let center = hand.pose.pinchPoint
        let radius: CGFloat = hand.isPinching ? 9 : 16
        let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        let color = hand.isPinching ? HoloStyle.accent : HoloStyle.color
        if hand.isPinching {
            context.fill(ring, with: .color(color.opacity(0.45)))
        }
        context.stroke(ring, with: .color(color), lineWidth: 2)
    }

    private func drawSummonProgress(of hand: TrackedHand, hold: TimeInterval, in context: inout GraphicsContext) {
        let progress = min(hand.stillOpenDuration / hold, 1)
        var arc = Path()
        arc.addArc(
            center: hand.pose.palmCenter,
            radius: hand.pose.handSize * 0.55,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * progress),
            clockwise: false
        )
        context.stroke(arc, with: .color(HoloStyle.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }
}

/// ホログラム風のパネル。基準サイズで描き、拡大縮小は呼び出し側で行う。
private struct HoloPanelView: View {
    let phase: HUDPhase
    let scale: CGFloat

    @State private var hasAppeared = false

    private var isActive: Bool { phase == .grabbed || phase == .scaling }
    private var tint: Color { isActive ? HoloStyle.accent : HoloStyle.color }

    private var statusText: String {
        switch phase {
        case .grabbed: "MOVE"
        case .scaling: "SCALE"
        case .idle, .hidden: "STANDBY"
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.22), tint.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            RoundedRectangle(cornerRadius: 10)
                .stroke(tint.opacity(0.8), lineWidth: 1)
            CornerBrackets()
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("MFX // PANEL 01")
                    Spacer()
                    Text(statusText)
                }
                .font(.system(size: 9, weight: .semibold, design: .monospaced))

                TimelineView(.animation) { timeline in
                    HStack(spacing: 14) {
                        RingGauge(date: timeline.date)
                            .frame(width: 70, height: 70)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(timeline.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
                                .font(.system(size: 24, weight: .light, design: .monospaced))
                            Text("SCALE ×\(scale, specifier: "%.2f")")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                            LevelBars(date: timeline.date)
                                .frame(height: 12)
                        }
                    }
                }
            }
            .padding(14)
        }
        .foregroundStyle(tint)
        .shadow(color: tint.opacity(0.8), radius: isActive ? 14 : 6)
        .scaleEffect(hasAppeared ? 1 : 0.3)
        .animation(.spring(duration: 0.35, bounce: 0.3), value: hasAppeared)
        .animation(.easeOut(duration: 0.15), value: isActive)
        .onAppear { hasAppeared = true }
    }
}

private struct CornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let length: CGFloat = 16
        let r = rect.insetBy(dx: -4, dy: -4)
        var path = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: r.minX, y: r.minY), 1, 1),
            (CGPoint(x: r.maxX, y: r.minY), -1, 1),
            (CGPoint(x: r.maxX, y: r.maxY), -1, -1),
            (CGPoint(x: r.minX, y: r.maxY), 1, -1),
        ]
        for (corner, dx, dy) in corners {
            path.move(to: CGPoint(x: corner.x + length * dx, y: corner.y))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + length * dy))
        }
        return path
    }
}

/// 逆方向に回る 2 本の弧と、秒に合わせて進む内側のリング。
private struct RingGauge: View {
    let date: Date

    var body: some View {
        let seconds = date.timeIntervalSinceReferenceDate
        ZStack {
            Circle()
                .stroke(lineWidth: 1)
                .opacity(0.35)
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(seconds * 90))
            Circle()
                .trim(from: 0, to: 0.18)
                .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-seconds * 140))
                .padding(8)
            Circle()
                .trim(from: 0, to: seconds.truncatingRemainder(dividingBy: 60) / 60)
                .stroke(lineWidth: 1.5)
                .rotationEffect(.degrees(-90))
                .padding(16)
                .opacity(0.8)
        }
    }
}

/// 時間でゆらぐレベルメーター。
private struct LevelBars: View {
    let date: Date

    var body: some View {
        let seconds = date.timeIntervalSinceReferenceDate
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<14, id: \.self) { index in
                let level = 0.35 + 0.65 * abs(sin(seconds * 2.2 + Double(index) * 0.7))
                Capsule()
                    .frame(width: 4)
                    .scaleEffect(y: level, anchor: .bottom)
                    .opacity(0.5 + 0.5 * level)
            }
        }
    }
}
