import CoreGraphics

/// 合成した手の形。テストと、カメラのないシミュレータでのデモに使う。
public enum SyntheticHandShape: Equatable, Sendable {
    case open
    case fist
    /// 親指と人差し指の先端の距離を `handSize` に対する比率で指定する。
    case pinch(gap: CGFloat)
}

extension HandPose {
    /// 指先が画面上方向を向き、`handSize` が `size` になる手を作る。
    public static func synthetic(
        wrist: CGPoint,
        size: CGFloat = 100,
        shape: SyntheticHandShape = .open
    ) -> HandPose {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: wrist.x + x * size, y: wrist.y + y * size)
        }

        var joints: [HandJoint: CGPoint] = [
            .wrist: p(0, 0),
            .thumbCMC: p(-0.35, -0.25),
            .thumbMP: p(-0.6, -0.45),
            .thumbIP: p(-0.75, -0.6),
            .thumbTip: p(-0.9, -0.7),
            .indexMCP: p(-0.3, -0.95),
            .middleMCP: p(0, -1.0),
            .ringMCP: p(0.25, -0.95),
            .littleMCP: p(0.5, -0.85),
        ]

        let fingers: [(pip: HandJoint, dip: HandJoint, tip: HandJoint, x: CGFloat)] = [
            (.indexPIP, .indexDIP, .indexTip, -0.3),
            (.middlePIP, .middleDIP, .middleTip, 0),
            (.ringPIP, .ringDIP, .ringTip, 0.25),
            (.littlePIP, .littleDIP, .littleTip, 0.5),
        ]

        for finger in fingers {
            if shape == .fist {
                joints[finger.pip] = p(finger.x, -1.3)
                joints[finger.dip] = p(finger.x, -1.1)
                joints[finger.tip] = p(finger.x, -0.9)
            } else {
                joints[finger.pip] = p(finger.x, -1.4)
                joints[finger.dip] = p(finger.x, -1.65)
                joints[finger.tip] = p(finger.x, -1.85)
            }
        }

        if case .pinch(let gap) = shape {
            joints[.thumbTip] = p(-0.5 - gap / 2, -1.2)
            joints[.indexTip] = p(-0.5 + gap / 2, -1.2)
        }

        return HandPose(uncheckedJoints: joints)
    }
}
