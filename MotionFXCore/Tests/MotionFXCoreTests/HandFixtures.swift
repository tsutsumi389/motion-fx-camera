import CoreGraphics
@testable import MotionFXCore

typealias HandShape = SyntheticHandShape

extension SyntheticHandShape {
    static let pinch = SyntheticHandShape.pinch(gap: 0.1)
}

func makeHand(
    wrist: CGPoint,
    size: CGFloat = 100,
    shape: HandShape = .open
) -> HandPose {
    .synthetic(wrist: wrist, size: size, shape: shape)
}

let frame: Double = 1.0 / 30.0
