import CoreMedia
import MotionFXCore
import Vision

/// カメラのフレームから手の関節を検出する。処理はすべて端末内で完結する。
final class HandPoseDetector {
    private static let jointMap: [VNHumanHandPoseObservation.JointName: HandJoint] = [
        .wrist: .wrist,
        .thumbCMC: .thumbCMC, .thumbMP: .thumbMP, .thumbIP: .thumbIP, .thumbTip: .thumbTip,
        .indexMCP: .indexMCP, .indexPIP: .indexPIP, .indexDIP: .indexDIP, .indexTip: .indexTip,
        .middleMCP: .middleMCP, .middlePIP: .middlePIP, .middleDIP: .middleDIP, .middleTip: .middleTip,
        .ringMCP: .ringMCP, .ringPIP: .ringPIP, .ringDIP: .ringDIP, .ringTip: .ringTip,
        .littleMCP: .littleMCP, .littlePIP: .littlePIP, .littleDIP: .littleDIP, .littleTip: .littleTip,
    ]

    private let minimumConfidence: Float = 0.3
    /// 手の大きさとピンチに必須の関節は、つまんで隠れがちなので低い信頼度でも採用する。
    /// これらが欠けると手ごと見失い、掴んでいるパネルを落としてしまうため。
    private let minimumRequiredConfidence: Float = 0.1
    private let request: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        return request
    }()

    /// 検出した手ごとの関節位置を返す。
    /// 座標は capture device 座標（センサー本来の向きで左上原点、0...1）。
    func detect(in sampleBuffer: CMSampleBuffer) -> [[HandJoint: CGPoint]] {
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        return (request.results ?? []).compactMap { observation in
            guard let points = try? observation.recognizedPoints(.all) else { return nil }
            var joints: [HandJoint: CGPoint] = [:]
            for (name, joint) in Self.jointMap {
                let threshold = HandPose.requiredJoints.contains(joint) ? minimumRequiredConfidence : minimumConfidence
                guard let point = points[name], point.confidence >= threshold else { continue }
                // Vision は左下原点なので、上下を反転して左上原点にそろえる。
                joints[joint] = CGPoint(x: point.location.x, y: 1 - point.location.y)
            }
            return joints.isEmpty ? nil : joints
        }
    }
}
