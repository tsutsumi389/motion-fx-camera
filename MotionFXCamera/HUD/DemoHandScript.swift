import CoreGraphics
import Foundation
import MotionFXCore

/// カメラのないシミュレータ用に、一連のジェスチャーを合成した手で再生する台本。
/// 出す → 掴んで動かす → 両手で拡大 → 離す → 払って消す、を 12 秒周期で繰り返す。
enum DemoHandScript {
    static let period: TimeInterval = 12
    private static let handSize: CGFloat = 70

    static func hands(at time: TimeInterval, in size: CGSize) -> [HandPose] {
        let t = time.truncatingRemainder(dividingBy: period)

        let startWrist = CGPoint(x: size.width * 0.55, y: size.height * 0.72)
        // パネルが出る位置（手のひらの中心 = 手首の 0.6 上、そこから handSize の 1.6 倍だけ上）。
        let panelCenter = CGPoint(x: startWrist.x, y: startWrist.y - 2.2 * handSize)
        let dragTarget = CGPoint(x: panelCenter.x - 50, y: panelCenter.y - 120)
        let leftStart = CGPoint(x: dragTarget.x - 100, y: dragTarget.y)
        let leftEnd = CGPoint(x: dragTarget.x - 125, y: dragTarget.y)
        let rightEnd = CGPoint(x: dragTarget.x + 25, y: dragTarget.y)

        switch t {
        case ..<1.3:
            return [open(startWrist)]
        case ..<2.0:
            return [open(lerp(startWrist, wrist(forPinchAt: panelCenter), progress(t, 1.3, 2.0)))]
        case ..<2.4:
            return [pinch(panelCenter)]
        case ..<3.8:
            return [pinch(lerp(panelCenter, dragTarget, progress(t, 2.4, 3.8)))]
        case ..<4.3:
            return [pinch(dragTarget)]
        case ..<5.8:
            let u = progress(t, 4.3, 5.8)
            return [pinch(lerp(dragTarget, rightEnd, u)), pinch(lerp(leftStart, leftEnd, u))]
        case ..<6.3:
            return [pinch(rightEnd), pinch(leftEnd)]
        case ..<7.0:
            return [open(wrist(forPinchAt: rightEnd)), open(wrist(forPinchAt: leftEnd))]
        case ..<8.5:
            return []
        case ..<8.9:
            let from = CGPoint(x: size.width * 0.15, y: size.height * 0.5)
            let to = CGPoint(x: size.width * 0.85, y: size.height * 0.5)
            return [open(lerp(from, to, CGFloat((t - 8.5) / 0.4)))]
        default:
            return []
        }
    }

    private static func open(_ wrist: CGPoint) -> HandPose {
        .synthetic(wrist: wrist, size: handSize, shape: .open)
    }

    private static func pinch(_ point: CGPoint) -> HandPose {
        .synthetic(wrist: wrist(forPinchAt: point), size: handSize, shape: .pinch(gap: 0.1))
    }

    /// つまんだ指先が `point` に来る手首の位置。
    private static func wrist(forPinchAt point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + 0.5 * handSize, y: point.y + 1.2 * handSize)
    }

    /// 区間内の進み具合を、なめらかな加減速つきの 0...1 で返す。
    private static func progress(_ t: TimeInterval, _ start: TimeInterval, _ end: TimeInterval) -> CGFloat {
        let u = CGFloat(min(max((t - start) / (end - start), 0), 1))
        return u * u * (3 - 2 * u)
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ u: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
    }
}
