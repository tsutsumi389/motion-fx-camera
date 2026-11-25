import CoreGraphics
import Foundation

/// ジェスチャー判定のしきい値。距離の比率はすべて `HandPose.handSize` が基準。
public struct GestureConfig: Equatable, Sendable {
    // MARK: ピンチ

    /// この比率を下回るとピンチ開始。
    public var pinchStartRatio: CGFloat = 0.3
    /// この比率を上回るとピンチ終了。開始より大きくしてチャタリングを防ぐ。
    public var pinchEndRatio: CGFloat = 0.5

    // MARK: 手のひら

    public var fingerExtensionRatio: CGFloat = 1.1
    /// 「開いていない」判定がこの秒数以内なら、開いた手として数え続ける（関節の取りこぼし対策）。
    public var openGrace: TimeInterval = 0.15
    /// 静止を判定する時間窓（秒）。
    public var stillWindow: TimeInterval = 0.2
    /// `stillWindow` の間、手のひらがこの範囲内に収まっていれば「静止している」とみなす。
    /// 1 フレームごとの速さではなく窓全体で見るので、検出位置の細かい揺れでは途切れない。
    public var stillRadius: CGFloat = 0.25
    /// 手のひらを開いて静止し続けるとパネルが出るまでの秒数。
    public var summonHold: TimeInterval = 0.4
    /// パネルを手のひらのどれだけ上に出すか。
    public var summonOffset: CGFloat = 1.6

    // MARK: スワイプ

    public var swipeWindow: TimeInterval = 0.3
    public var swipeMinDuration: TimeInterval = 0.08
    /// `swipeWindow` 内にこの距離を横に動くとスワイプ。
    public var swipeDistance: CGFloat = 1.5
    /// 手を見失った時間がこれより長ければ、スワイプの軌跡をやり直す（再検出時の位置飛びを数えない）。
    /// 処理が遅くてフレーム間隔が長いだけの場合は、途切れとして扱わない。
    public var swipeMaxGap: TimeInterval = 0.1
    /// 消した直後に同じ手で出し直さないための待ち時間。
    public var dismissCooldown: TimeInterval = 1.0

    // MARK: トラッキング

    /// 前フレームの手と同一とみなす手首の移動距離の上限。
    public var matchDistance: CGFloat = 2.0
    /// 検出が途切れても同じ手として待つ秒数。
    public var trackTimeout: TimeInterval = 0.3

    // MARK: パネル

    public var panelBaseSize = CGSize(width: 240, height: 150)
    /// パネルの外側でも掴める余白（ポイント）。
    public var grabMargin: CGFloat = 30
    /// 拡大縮小に加わる 2 本目の手が、掴める範囲からさらにどれだけ離れていてよいか（ポイント）。
    public var scaleReach: CGFloat = 80
    public var minScale: CGFloat = 0.5
    public var maxScale: CGFloat = 2.5

    public init() {}
}
