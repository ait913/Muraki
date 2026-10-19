---
title: "iOS 26 の BGContinuedProcessingTask で GPU (background GPU access) は iPhone では使えない"
category: gotcha
project: bloom
tags: [ios, background-tasks, bgcontinuedprocessingtask, gpu, entitlement, xcode-cloud]
created: 2026-10-12
sources:
  - https://developer.apple.com/forums/thread/801229
  - https://developer.apple.com/forums/thread/816774
  - https://developer.apple.com/videos/play/wwdc2025/227/
---

## Context
bloom 0.2.2 で「帰宅したらアプリを閉じたまま旅 vlog (MapLibre の地図フレーム描画 + 動画書き出し) を作る」ために `BGContinuedProcessingTask` + `requiredResources = .gpu` を設計した。

## What
- `com.apple.developer.background-tasks.continued-processing.gpu` は申請制 (Capability Requests) ではなく通常の capability。だが **Apple DTS 曰く、background GPU は M3 以降の iPad のみ対応で iPhone は全機種非対応** (iPhone 15 Pro / 16 Pro で `supportedResources` に `.gpu` が無い報告あり)。
- App ID に capability を付けないまま entitlement だけ足すと、Xcode Cloud の export が `Automatic signing cannot update bundle identifier "<id>"` / `No profiles for '<id>'` で落ちる (bloom dev build 10023)。

## Why
Apple が GPU のバックグラウンド実行をハードウェアで制限している (OS の許可・申請の問題ではない)。

## How to apply
- iPhone アプリで「閉じたまま GPU 描画 (地図・Metal・動画合成の描画部分)」を前提にした設計をしない。検知は背景 (region monitoring 等)、描画は前景で開いたら自動開始、通知文面はその挙動に合わせる (`knowledge/pattern/ios-background-detect-foreground-render.md`)。
- iPad 対応アプリで使う場合も、実行時に `BGTaskScheduler.shared.supportedResources.contains(.gpu)` を確認して CPU フォールバックを持つ。
