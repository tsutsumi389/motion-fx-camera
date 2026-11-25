import MotionFXCore
import SwiftUI

struct ContentView: View {
    @StateObject private var model = HUDViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                background
                HUDOverlayView(state: model.state, config: model.config)
            }
            .onAppear { model.viewSize = proxy.size }
            .onChange(of: proxy.size) { _, size in model.viewSize = size }
        }
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) { cameraSwitchButton }
        .overlay(alignment: .bottom) { hint }
        .statusBarHidden()
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            model.setActive(phase == .active)
        }
    }

    @ViewBuilder
    private var background: some View {
        switch model.access {
        case .granted:
            CameraPreviewView(session: model.camera.session) { layer in
                model.previewLayer = layer
            }
        case .demo:
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.07, blue: 0.12), .black],
                startPoint: .top,
                endPoint: .bottom
            )
        case .denied:
            Color.black.overlay {
                cameraUnavailableMessage(
                    "手の動きを検出するには、設定でカメラへのアクセスを許可してください。",
                    showsSettingsButton: true
                )
            }
        case .failed:
            Color.black.overlay {
                cameraUnavailableMessage(
                    "カメラを起動できませんでした。ほかのアプリがカメラを使っていないか確認して、アプリを開き直してください。",
                    showsSettingsButton: false
                )
            }
        case .unknown:
            Color.black
        }
    }

    private func cameraUnavailableMessage(_ message: String, showsSettingsButton: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 40))
            Text("カメラを使用できません")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if showsSettingsButton {
                Button("設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
    }

    @ViewBuilder
    private var cameraSwitchButton: some View {
        if model.access == .granted {
            Button {
                model.switchCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .tint(HoloStyle.color)
            .padding(.trailing, 16)
            .accessibilityLabel("カメラを切り替える")
        }
    }

    @ViewBuilder
    private var hint: some View {
        if let text = hintText {
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .foregroundStyle(HoloStyle.color)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(.bottom, 8)
        }
    }

    private var hintText: String? {
        guard model.access == .granted || model.access == .demo else { return nil }
        let prefix = model.access == .demo ? "DEMO ・ " : ""
        switch model.state.phase {
        case .hidden: return prefix + "手のひらを開いて止める → パネル表示"
        case .idle: return prefix + "つまむ → 移動 ・ 横に払う → 消す"
        case .grabbed: return prefix + "もう片方の手もつまむ → 拡大縮小"
        case .scaling: return prefix + "両手を広げる・縮める"
        }
    }
}

#Preview {
    ContentView()
}
