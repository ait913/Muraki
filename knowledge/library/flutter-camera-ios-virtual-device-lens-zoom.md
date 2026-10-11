---
title: Flutter camera (iOS) で純正カメラ風の 0.5x/1x/3x シームレス切替 — 仮想デバイスと videoZoomFactor
category: library
project: bloom
tags: [flutter, camera, ios, ultra-wide, virtual-device, videoZoomFactor]
created: 2026-10-11
sources:
  - ~/.pub-cache/hosted/pub.dev/camera_avfoundation-0.10.2/ios/camera_avfoundation/Sources/camera_avfoundation/CameraPlugin.swift:30-36,125-150 (deviceFactory = AVCaptureDevice(uniqueID: name)!、discovery は wide/tele/ultraWide の物理 3 種のみ)
  - iPhoneOS26.5.sdk AVFoundation/AVCaptureDevice.h:530-562 (DualWide/Triple 仮想デバイス), :778-785 (virtualDeviceSwitchOverVideoZoomFactors), :2232-2239 (minAvailableVideoZoomFactor), :1982-1989 (displayVideoZoomFactorMultiplier, iOS 18+)
  - https://developer.apple.com/forums/thread/719602 (Apple DTS: iPhone 14 Pro の min=1.0 が 0.5x、switchOver [2,6] が 1x/3x)
---

## Context
camera 0.12.0+2 / camera_avfoundation 0.10.2 のまま「.5 / 1x / 2x / 3x」ボタンと連続ピンチでレンズ切替をしたい時の実現手段。

## What
- プラグインの `availableCameras()` は物理 3 種 (`builtInWideAngle` / `Telephoto` / `UltraWide`) だけを返す。**仮想デバイス (Triple / DualWide / Dual) は返さない** (pub.dev 最新の camera_avfoundation 0.11.0 / camera 0.12.1 の changelog に仮想デバイス対応の記載なし。0.11.0 のソース実読は未実施)。back の先頭は wide (SDK 26.5 のヘッダ:2868 の sorted 仕様)。
- ただし `create(cameraName)` は `AVCaptureDevice(uniqueID: name)` で端末を引くだけ → **仮想デバイスの uniqueID を Dart から `CameraDescription(name: …)` に渡せば fork 不要で使える** (ID は Runner 側の小さな MethodChannel で `AVCaptureDevice.DiscoverySession([.builtInTripleCamera,.builtInDualWideCamera,.builtInDualCamera], .video, .back)` から取る)。
- 仮想デバイスの `videoZoomFactor` 1.0 = 最広角レンズ。超広角ありの端末では 1.0 = 表示 0.5x、`virtualDeviceSwitchOverVideoZoomFactors[0]` (例 2.0) = 表示 1x、[1] (例 6.0) = 3x。超広角なし (旧 DualCamera) は 1.0 = 1x。表示倍率 = factor / switchOver[0] (超広角あり) とするのが確実。`displayVideoZoomFactorMultiplier` は iOS 18+ で、iPhone で 0.5 を返す実測は未確認。
- `setZoomLevel` は `videoZoomFactor` を直接代入 (snap)。仮想デバイスのレンズ切替は同一 AVCaptureSession 内で起きるので controller 再作成・暗転なし。初期ズームは必ず switchOver[0] にする (既定 1.0 は超広角で始まる)。

## Why
物理デバイスごとに controller を作り直す現行方式 (bloom `s4_capture.dart` `_initCamera`) は dispose → initialize で必ず途切れる。

## How to apply
実機未検証 (シミュレータにカメラ無し): 仮想デバイス + `ResolutionPreset.veryHigh` + `setVideoStabilizationMode(level1)` + AVAssetWriter 録画 + takePicture の組合せは、実機 1 台で録画/写真/手ブレ補正の 3 点を確認してから確定すること。
bloom の採用形 (.designs/20261011-capture-lens-multigroup-segment.md D3〜D6): Runner の既存 channel に `captureLenses` を 1 case 足して uniqueID と switchOver を返し、Dart で `CameraDescription(name: uniqueID, lensDirection: back, sensorOrientation: 90)`。ボタンの移行は Runner の `rampToVideoZoomFactor` を使わず (プラグインと同じ AVCaptureDevice インスタンスに lock する保証が無い)、Dart 側で 250ms の段階 `setZoomLevel` を「処理中 1 件 + 最新 1 件」に間引いて送る。
