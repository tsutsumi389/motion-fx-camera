import AVFoundation
import MotionFXCore
import QuartzCore
import SwiftUI

@MainActor
final class HUDViewModel: ObservableObject {
    enum CameraAccess {
        case unknown, granted, denied
        /// スクリーンタイムなどで制限されていて、ユーザー自身では許可できない。
        case restricted
        /// 許可はあるがカメラを起動できなかった。
        case failed
        /// シミュレータ。カメラがないので合成した手でデモを流す。
        case demo
    }

    @Published private(set) var state = HUDState()
    @Published private(set) var access = CameraAccess.unknown

    let camera = CameraController()
    weak var previewLayer: AVCaptureVideoPreviewLayer?
    /// デモ用。実機ではプレビューレイヤーの大きさを使う。
    var viewSize = CGSize.zero

    private var interactor = HUDInteractor()
    private var demoTask: Task<Void, Never>?
    private var isActive = true
    /// このカメラで撮ったフレームだけを処理する。切り替え中は nil にしてすべて捨てる。
    /// 切り替え前のフレームを切り替え後のプレビュー（左右反転が変わる）で変換しないため。
    private var acceptedPosition: AVCaptureDevice.Position? = .back

    var config: GestureConfig { interactor.config }

    func start() async {
        guard access == .unknown else { return }
        #if targetEnvironment(simulator)
        access = .demo
        startDemo()
        #else
        switch await CameraController.requestAccess() {
        case .granted:
            break
        case .denied:
            access = .denied
            return
        case .restricted:
            access = .restricted
            return
        }
        access = .granted
        camera.onFrame = { [weak self] frame in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.handle(frame)
                }
            }
        }
        camera.onSetupFailed = { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.access = .failed
                }
            }
        }
        // 許可のダイアログが出ている間にバックグラウンドへ移っていたら、ここでは始めない。
        // 戻ってきたときに setActive(true) が始める。
        if isActive {
            camera.start()
        }
        #endif
    }

    func setActive(_ isActive: Bool) {
        self.isActive = isActive
        switch access {
        case .granted:
            if isActive { camera.start() } else { camera.stop() }
        case .demo:
            if isActive { startDemo() } else { stopDemo() }
        case .failed:
            // 戻ってきたときにはカメラが使えるようになっているかもしれないので、起動し直す。
            if isActive {
                access = .granted
                camera.start()
            }
        case .unknown, .denied, .restricted:
            break
        }
        if !isActive {
            clear()
        }
    }

    func switchCamera() {
        guard access == .granted, acceptedPosition != nil else { return }
        acceptedPosition = nil
        clear()
        camera.switchCamera { [weak self] position in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.acceptedPosition = position
                    self?.clear()
                }
            }
        }
    }

    private func clear() {
        interactor.reset()
        state = HUDState()
    }

    private func handle(_ frame: HandFrame) {
        // 停止や切り替えの前にキューへ入っていた古いフレームは捨てる。
        guard isActive, frame.position == acceptedPosition, let layer = previewLayer else { return }
        let poses = frame.hands.compactMap { joints in
            HandPose(joints: joints.mapValues { layer.layerPointConverted(fromCaptureDevicePoint: $0) })
        }
        process(poses, at: frame.time, bounds: layer.bounds)
    }

    private func process(_ poses: [HandPose], at time: TimeInterval, bounds: CGRect) {
        interactor.bounds = bounds
        state = interactor.update(hands: poses, at: time)
    }

    // MARK: デモ

    private func startDemo() {
        guard demoTask == nil else { return }
        let startedAt = CACurrentMediaTime()
        demoTask = Task { [weak self] in
            while !Task.isCancelled {
                // 待っている間は self を保持しない。解放されていたらループを終える。
                guard self?.demoTick(startedAt: startedAt) != nil else { return }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func demoTick(startedAt: TimeInterval) {
        guard viewSize != .zero else { return }
        let now = CACurrentMediaTime()
        let poses = DemoHandScript.hands(at: now - startedAt, in: viewSize)
        process(poses, at: now, bounds: CGRect(origin: .zero, size: viewSize))
    }

    private func stopDemo() {
        demoTask?.cancel()
        demoTask = nil
    }
}
