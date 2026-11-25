import AVFoundation
import SwiftUI

/// カメラ映像を画面いっぱいに表示する。
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// 検出座標を画面座標へ変換するために、プレビューレイヤーを渡す。
    let onLayerReady: (AVCaptureVideoPreviewLayer) -> Void

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        onLayerReady(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // layerClass で指定しているので必ず成功する。
        layer as! AVCaptureVideoPreviewLayer
    }
}
