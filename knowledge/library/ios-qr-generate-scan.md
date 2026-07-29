---
title: iOS QR コード 生成 (CoreImage) / スキャン (VisionKit DataScanner)
category: library
project: null
tags: [ios, swiftui, qrcode, coreimage, visionkit, camera, deeplink]
created: 2026-07-21
sources:
  - https://developer.apple.com/tutorials/data/documentation/visionkit/datascannerviewcontroller.json
  - https://developer.apple.com/documentation/coreimage/cifilter
---

## Context
アプリ内 QR 招待 (友達追加/ルーム招待) を SwiftUI (iOS 17 target) で実装するときの標準 API。外部ライブラリ不要。すべて compile-verified (swiftc -typecheck, iOS17 simulator target)。

## What
**生成 = CoreImage、外部依存ゼロ。** iOS 13+ の typed builtin filter:
```swift
import CoreImage.CIFilterBuiltins
let f = CIFilter.qrCodeGenerator()
f.message = Data(urlString.utf8)
f.correctionLevel = "M"            // L/M/Q/H
let out = f.outputImage!           // 小さい (~25px)、.transformed(by: .init(scaleX:10,y:10)) で拡大
let cg = CIContext().createCGImage(out, from: out.extent)!
let img = UIImage(cgImage: cg)
```

**スキャン = VisionKit `DataScannerViewController` (iOS 16.0+)。** UIViewController なので `UIViewControllerRepresentable` で包む。
- `DataScannerViewController.isSupported` (端末が Neural Engine 等を持つか), `.isAvailable` (supported かつカメラ権限 granted)
- init: `recognizedDataTypes: [.barcode(symbologies: [.qr])]`, `qualityLevel:`, `recognizesMultipleItems:`, `isHighFrameRateTrackingEnabled:`, `isHighlightingEnabled:`
- `try vc.startScanning()`, delegate `didAdd`/`didTapOn` で `RecognizedItem.barcode(let b)` → `b.payloadStringValue`
- ★ **シミュレータでは isSupported=false**。実機必須 (Reviewer の E2E 注意)
- 代替 = `AVFoundation` `AVCaptureMetadataOutput` (iOS 6+、metadataObjectTypes=[.qr])。低レベルだが実機なしの制御性。SwiftUI では DataScanner の方が短い。

## Why
CoreImage QR は Apple 標準で `import` だけで使える (プロジェクトに zxing 等を入れる必要なし)。DataScanner はカメラプレビュー+検出+ハイライトを 1 VC で完結。

## How to apply
1. **カメラ権限必須**: Info.plist に `NSCameraUsageDescription`。XcodeGen プロジェクトは `project.yml` の `targets.<T>.info.properties` に追記 (Info.plist 手編集不可な構成が多い)。
2. スキャン結果は「文字列」で得られる。招待 URL をそのまま `URL(string:)` → 既存の DeepLink パーサ/join API に渡せば、universal link 経路を経ずにアプリ内で完結 (バックエンド変更不要)。
