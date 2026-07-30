---
title: Expo SDK 57 で QR を読む / 出す (expo-barcode-scanner は SDK 52 で削除済)
category: library
tags: [expo, sdk57, qr, barcode, expo-camera, react-native-svg]
created: 2026-07-30
project: global
sources:
  - https://docs.expo.dev/versions/v57.0.0/sdk/camera/
  - https://expo.dev/changelog/2024/11-12-sdk-52
  - https://raw.githubusercontent.com/expo/expo/sdk-57/packages/expo-camera/src/index.ts
  - https://raw.githubusercontent.com/expo/expo/sdk-57/packages/expo-camera/src/CameraView.tsx
  - https://raw.githubusercontent.com/expo/expo/sdk-57/packages/expo/bundledNativeModules.json
  - https://raw.githubusercontent.com/expo/expo/sdk-57/apps/expo-go/package.json
---

## Context

omatase (Expo SDK 57 / RN 0.86 / newArchEnabled) の招待 QR 設計前の一次確認 (2026-07-30)。

## What

**スキャン側 = expo-camera 一択。`expo-barcode-scanner` は SDK 52 で削除済**
(公式文: 「`expo-barcode-scanner` has been removed: it was deprecated in SDK 50 and slated for
removal in SDK 51. The barcode scanning functionality provided by `expo-camera` is a better
alternative」)。npm の最終公開は 14.0.1 / 2024-10-22 で `deprecated` フィールドは付いていない
(= npm を見ても廃止に見えない)。`docs.expo.dev/versions/v57.0.0/sdk/bar-code-scanner/` は 404。

SDK 57 のピンは **expo-camera 57.0.3** (`bundledNativeModules.json`)。API は 2 系統:

1. **インラインプレビュー**: `<CameraView onBarcodeScanned={(r: BarcodeScanningResult) => …}
   barcodeScannerSettings={{ barcodeTypes: ['qr'] }} />`
2. **OS ネイティブのモーダルスキャナ** (iOS 16+ の `DataScannerViewController`):
   `CameraView.isModernBarcodeScannerAvailable` (static boolean) →
   `await CameraView.launchScanner({ barcodeTypes: ['qr'] })` /
   `CameraView.onModernBarcodeScanned(listener) → EventSubscription` /
   `CameraView.dismissScanner()`。**Platform.OS !== 'web' かつ available の時だけ実行される**
   (それ以外は静かに no-op)
3. 画像から読む: `scanFromURLAsync(url, ['qr'])` — **iOS は QR のみ対応**

権限は `useCameraPermissions()` (`createPermissionHook`)。iOS は **`NSCameraUsageDescription`** が必須。
config plugin プロパティは `cameraPermission` / `microphonePermission` / `recordAudioAndroid` /
`barcodeScannerEnabled`。`barcodeTypes` の値は
`'aztec'|'ean13'|'ean8'|'qr'|'pdf417'|'upc_e'|'datamatrix'|'code39'|'code93'|'itf14'|'codabar'|'code128'|'upc_a'`。

**生成側 = react-native-qrcode-svg 6.3.21** (2025-12-04)。ネイティブコード無しの純 JS で、
`react-native-svg` の上に乗るだけ (peer: `react-native-svg >=14.0.0`)。★ **メンテナは Expensify に
移っており生きている** (repo `Expensify/react-native-qrcode-svg`, 2026-05 push, 1.1k stars)。
SDK 57 のピンは `react-native-svg 15.15.4` で、Fabric は **react-native-svg 13.0.0 以降が対応**。
代替: `react-native-qrcode-styled` 0.4.0 (svg 系, デザイン自由度高) /
`react-native-qrcode-skia` 0.4.0 (`@shopify/react-native-skia` が必要 = 依存が重い)。

★ **expo-camera / react-native-svg / react-native-maps / datetimepicker はいずれも Expo Go SDK 57
に同梱されている** (`apps/expo-go/package.json` に `expo-camera workspace:*`,
`react-native-svg 15.15.4`, `react-native-maps 1.27.2`, `@react-native-community/datetimepicker ^9.1.0`)。
→ **QR のスキャンも生成も dev build を待たずに Expo Go で検証できる**。

## Why

Expo は SDK 50 で barcode-scanner を deprecate、52 で削除して expo-camera に統合した。
npm 側に `deprecated` を打っていないので「まだ生きている」と誤認しやすい。
QR 生成は SVG を描くだけなのでネイティブ実装が要らず、New Architecture の互換性は
react-native-svg 側にしか依存しない。

## How to apply

- スキャン UI は `CameraView` + `onBarcodeScanned` を基本形にする。iOS 16+ で OS 標準の見た目を
  出したい場合だけ `launchScanner` を足す (フォールバック必須: `isModernBarcodeScannerAvailable`)
- `app.config.ts` の `ios.infoPlist` に `NSCameraUsageDescription` を必ず書く
  (expo-location の `NSLocationWhenInUseUsageDescription` と同じ扱い)
- 生成は `react-native-qrcode-svg` + `npx expo install react-native-svg` (57 系は 15.15.4 が入る)
- 「Expo Go で動くか」は `apps/expo-go/package.json` を sdk-XX ブランチで見れば 1 発で分かる。
  `bundledNativeModules.json` は**バージョンのピン表であって Expo Go の同梱リストではない**
