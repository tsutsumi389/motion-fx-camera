import AVFoundation
import MotionFXCore

/// 1 フレームぶんの検出結果。
struct HandFrame: Sendable {
    /// 手ごとの関節位置。座標は capture device 座標（左上原点、0...1）。
    let hands: [[HandJoint: CGPoint]]
    /// フレームが撮影された時刻（秒）。処理の遅れに左右されない。
    let time: TimeInterval
    /// このフレームを撮ったカメラ。
    let position: AVCaptureDevice.Position
}

/// カメラの映像を取り込み、フレームごとに手の検出結果を通知する。
final class CameraController: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()

    /// 映像キューから呼ばれる。`start()` の前に設定すること。
    var onFrame: (@Sendable (HandFrame) -> Void)?
    /// カメラを構成できなかったときに呼ばれる。`start()` の前に設定すること。
    var onSetupFailed: (@Sendable () -> Void)?

    private let sessionQueue = DispatchQueue(label: "motionfx.camera.session")
    private let videoQueue = DispatchQueue(label: "motionfx.camera.video", qos: .userInteractive)
    private let detector = HandPoseDetector()

    // sessionQueue 上でのみ読み書きする。
    private var position = AVCaptureDevice.Position.back
    private var isConfigured = false
    private var wantsRunning = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError),
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )
    }

    /// メディアサービスのリセットなどでセッションが止まったら、動かしたい間は再開する。
    @objc private func sessionRuntimeError(_ notification: Notification) {
        sessionQueue.async { [self] in
            if wantsRunning, isConfigured, !session.isRunning {
                session.startRunning()
            }
        }
    }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    func start() {
        sessionQueue.async { [self] in
            wantsRunning = true
            if !isConfigured {
                configure()
            }
            guard isConfigured else {
                onSetupFailed?()
                return
            }
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            wantsRunning = false
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    /// 前面と背面を切り替える。切り替え後に実際に使われているカメラを `completion` に渡す
    /// （切り替えに失敗した場合は元のカメラ）。`completion` はセッションキューから呼ばれる。
    func switchCamera(completion: @escaping @Sendable (AVCaptureDevice.Position) -> Void) {
        sessionQueue.async { [self] in
            guard isConfigured else {
                completion(position)
                return
            }
            let previous = position
            position = previous == .back ? .front : .back
            session.beginConfiguration()
            if !replaceInput() {
                position = previous
                _ = replaceInput()
            }
            pinOutputConnections()
            session.commitConfiguration()
            completion(position)
        }
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .hd1280x720
        guard replaceInput() else { return }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        pinOutputConnections()

        isConfigured = true
    }

    /// 検出に使う映像を「センサー本来の向き・反転なし」に固定する。
    /// 画面座標への変換（回転と前面カメラの左右反転）はプレビューレイヤーに任せているので、
    /// ここで反転されると左右が二重に入れ替わってしまう。
    private func pinOutputConnections() {
        for output in session.outputs {
            guard let connection = output.connection(with: .video) else { continue }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
    }

    /// 現在の `position` のカメラを入力に差し替える。
    private func replaceInput() -> Bool {
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
            let input = try? AVCaptureDeviceInput(device: device)
        else { return false }

        let existing = session.inputs
        existing.forEach(session.removeInput)
        if session.canAddInput(input) {
            session.addInput(input)
            return true
        }
        existing.forEach { if session.canAddInput($0) { session.addInput($0) } }
        return false
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let position = connection.inputPorts.first?.sourceDevicePosition ?? .unspecified
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard time.isFinite else { return }
        onFrame?(HandFrame(hands: detector.detect(in: sampleBuffer), time: time, position: position))
    }
}
