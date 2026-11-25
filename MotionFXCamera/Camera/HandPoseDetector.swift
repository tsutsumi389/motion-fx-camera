import CoreMedia
import MotionFXCore
import OSLog
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
    /// 手の大きさとピンチに必須の関節は、つまんで隠れがちなので少しだけ緩める。
    /// 緩めすぎると当てずっぽうの位置が手の大きさの基準に入り、誤ってつまんだ判定になる。
    /// 一瞬の取りこぼしは `GestureConfig.trackTimeout` の間「掴んだまま待つ」ことで吸収する。
    private let minimumRequiredConfidence: Float = 0.2
    private let logger = Logger(subsystem: "MotionFXCamera", category: "HandPoseDetector")
    /// 同じ失敗を毎フレーム記録しないための印。映像キュー上でのみ読み書きする。
    private var isFailing = false
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
            isFailing = false
        } catch {
            // 失敗が続いても「手が写っていない」のと見分けがつくよう、最初の 1 回を記録する。
            if !isFailing {
                isFailing = true
                logger.error("Hand pose detection failed: \(error.localizedDescription, privacy: .public)")
            }
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
