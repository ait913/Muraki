---
title: Flutter camera 0.12 (iOS) の手ブレ補正 API と録画設定の実装位置 (camera_avfoundation 0.10.2 実読)
category: library
project: bloom
tags: [flutter, camera, ios, video-stabilization, avassetwriter, resolution]
created: 2026-10-10
sources:
  - /Applications/Xcode.app/.../iPhoneOS26.5.sdk/System/Library/Frameworks/AVFoundation.framework/Headers/AVCaptureDevice.h:3118-3134 / AVCaptureSession.h:1225-1233 (enum doc と preferredVideoStabilizationMode の既定値)
  - ~/.pub-cache/hosted/pub.dev/camera-0.12.0+2/lib/src/camera_controller.dart (setVideoStabilizationMode / getSupportedVideoStabilizationModes)
  - ~/.pub-cache/hosted/pub.dev/camera_avfoundation-0.10.2/ios/camera_avfoundation/Sources/camera_avfoundation/DefaultCamera.swift
---

## Context
bloom の「動画の手ブレがひどい」「閲覧側の画質が低い」の事前調査。camera プラグインだけで足りるか、自前 Swift が要るかの確認。

## What
- `camera 0.12.0+2` には `CameraController.setVideoStabilizationMode(VideoStabilizationMode, {allowFallback = true})` と `getSupportedVideoStabilizationModes()` が**ある** (enum: off / level1 / level2 / level3 = iOS の standard / cinematic / cinematicExtended)。platform channel も fork も不要。
- Swift 側 (`DefaultCamera.setVideoStabilizationMode`) は `captureVideoOutput.connection(.video).preferredVideoStabilizationMode` に設定。`activeFormat.isVideoStabilizationModeSupported` で弾き、非対応は `VIDEO_STABILIZATION_ERROR`。
- 一度も呼ばない場合のネイティブ既定は **Off** (iOS SDK 26.5 `AVCaptureSession.h` の `preferredVideoStabilizationMode` doc: 「The default value is AVCaptureVideoStabilizationModeOff」、iOS 6 以降リンクのアプリ。2026-10-10 に旧記述 `.auto` を訂正)。Dart 側 `value.videoStabilizationMode` の `off` も同じ。
- **プラグインで選べるのは off / standard / cinematic / cinematicExtended の 4 つだけ** (pigeon enum `PlatformVideoStabilizationMode` 0-3、`Messages.swift:202`)。`.auto` / `previewOptimized` (iOS 17) / `cinematicExtendedEnhanced` (iOS 18) / `lowLatency` (iOS 26) は fork か vendored 改造 (enum 追加 + pigeon 再生成) が要る。`previewOptimized` は preview layer か preview サイズの data output の接続専用で、録画の full-size data output には効かない (SDK `AVCaptureDevice.h:3128` の doc)。
- 強さの序列 (SDK header の doc): standard < cinematic (視野さらに狭く・遅延「much more」・メモリ「significantly more」) < cinematicExtended (さらに遅延・メモリ、安定は上) 。iPhone 純正カメラがどれを使うかを Apple は公開していない (Developer Forums の非公式回答が「standard 相当」と言うのみ、thread 127395)。
- 録画は AVCaptureMovieFileOutput でなく **AVAssetWriter** (`recommendedVideoSettingsForAssetWriter` を取り、`videoBitrate` と `fps` の**どちらか一方でも**非 null なら `AVVideoCompressionPropertiesKey` を丸ごと置換 — 推奨設定の profile・bitrate は落ち、指定したキーだけになる。`DefaultCamera.swift:599-610` 実読で確定。`AVVideoCodecKey` は外側の辞書なので推奨の codec は残る)。
- `takePicture()` は `fileFormat` 既定 = JPEG (`setImageFileFormat(heif)` を呼ばない限り HEIC は出ない)。`isHighResolutionPhotoEnabled` は preset `.max` のときだけ立つので、`veryHigh` のセッションでは写真もセッション解像度 (1920×1080) になる (`DefaultCamera.swift:706-731`)。
- `ResolutionPreset.high` = `hd1280x720`、`veryHigh` = `hd1920x1080`、`ultraHigh` = 4K (`DefaultCamera.swift:271-`)。
- レンズ切替は bloom のように controller を作り直す場合、補正モードも再設定が要る。

## Why
camera の changelog が "Adds video stabilization" (camera_avfoundation 側 CHANGELOG:24)。

## How to apply
`await controller.initialize()` の直後に `setVideoStabilizationMode(VideoStabilizationMode.level1)` (standard、allowFallback 既定 true で非対応は off)。**純正カメラの動画並みを狙うなら level1** — bloom で level2 (cinematic) を出したところ実機で「補正が強すぎる」(Touri FB 2026-10-10) となり level1 に戻した。cinematic 系は画角が狭まり遅延が増える。codec (H.264/HEVC) は未実測。
