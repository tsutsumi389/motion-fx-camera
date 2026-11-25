# motion-fx-camera

手のジェスチャーで、カメラ映像に浮かぶホログラム風パネルを操作する iOS アプリ。

## ジェスチャー

| ジェスチャー | 動作 |
|---|---|
| 手のひらを開いて止める | パネルを手の上に出す |
| 親指と人差し指でつまむ | パネルを掴む |
| つまんだまま動かす | パネルを移動 |
| 両手でつまんで広げる・縮める | 拡大・縮小 |
| 手を横に払う | パネルを消す |

映像と手の検出はすべて端末内で処理し、外部には送信しない。

## 構成

```
MotionFXCamera.xcodeproj   アプリのプロジェクト
MotionFXCamera/            アプリ本体（SwiftUI）
  Camera/                  カメラ取り込みと Vision による手の検出
  HUD/                     パネルと手の骨格の描画、デモ用の台本
MotionFXCore/              ジェスチャー判定（Swift パッケージ、UI とカメラに非依存）
```

`MotionFXCore` は手の関節座標の列を受け取り、パネルの状態を返す状態機械。
しきい値は `GestureConfig` にまとまっていて、すべて手の大きさに対する比率で判定する。

## 開発

必要なもの: Xcode 16 以降、iOS 17 以降の iPhone 実機。

```bash
open MotionFXCamera.xcodeproj
```

実機で動かすには、Xcode の Signing & Capabilities で Team を設定する。

シミュレータにはカメラがないので、合成した手で一連のジェスチャーを再生するデモが流れる。

### テスト

ジェスチャー判定のテストは macOS 上で実行できる。

```bash
cd MotionFXCore && swift test
```
