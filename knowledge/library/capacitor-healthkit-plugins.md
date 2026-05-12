---
title: Capacitor HealthKit プラグインの現状 (2026年5月)
category: library
tags: [capacitor, ios, healthkit, sleep, hrv]
created: 2026-05-11
project: global
sources:
  - https://github.com/Cap-go/capacitor-health
  - https://github.com/perfood/capacitor-healthkit
  - https://capgo.app/docs/plugins/health/
---

## Context
Capacitor iOS アプリから HealthKit の睡眠ステージ・心拍・HRV などを読みたい。2026年5月時点でどのプラグインが現役か、何ができて何ができないかを確定したい。

## What

### 推奨: `@capgo/capacitor-health` (Cap-go/capacitor-health)
- **最新 v8.4.9 (2026-05-04 リリース)**、Capacitor v8 系で active 維持
- iOS HealthKit + Android Health Connect を統一 API でラップ
- **睡眠ステージ対応**: `sleepState` フィールドが `'inBed' | 'asleep' | 'awake' | 'rem' | 'deep' | 'light'` を返す
- 取得可能: steps, distance, calories, heart rate, weight, sleep ほか
- **背景配信 (HKObserverQuery / enableBackgroundDelivery) は docs に記載なし** — 必要ならネイティブ Swift 追加実装が必要

### 旧主流: `@perfood/capacitor-healthkit`
- v1.3.2 (2025-02-13) で main ブランチは PR 受付停止、v2 ブランチに移行作業中で **半 stale**
- 睡眠ステージ詳細は documented sample types に含まれていない (`calories/stairs/activity/steps/distance/duration/weight`)
- 新規プロジェクトでは選ばない

### 旧称: `@capacitor-community/health-kit`
- メンテ停止、Perfood に引き継がれている

### ネイティブ Swift bridge (フォールバック)
- バックグラウンド取得 (HKObserverQuery + enableBackgroundDelivery) や HKWorkout の細かい型を扱う場合、結局 `AppDelegate.swift` + 自作 Capacitor plugin に行き着く
- アプリが force-quit 状態だと WebView は起動しないので、ネイティブ側で受け取って SQLite / ローカル通知に蓄積する必要

## 睡眠データの粒度・遅延
- iOS 16+ の `HKCategoryTypeIdentifierSleepAnalysis` で REM/Deep/Core/Awake が 30秒エポック単位で記録
- **iPhone のみ**: 加速度計+マイク+充電状態から「就寝中/起床中」程度しか判別できない (ステージなし)
- **Apple Watch 併用**: ステージ判別可、Awakenings 検出可、HRV (SDNN) 取得可
- データ反映: Watch の睡眠モード解除直後に iPhone と同期、通常数分以内で取得可能
- HRV (HKQuantityTypeIdentifierHeartRateVariabilitySDNN) は 2-5時間おき不定期サンプリング (Watch)、mindfulness 系アプリ使用後・睡眠中は頻度上昇

## 権限の落とし穴
- `Info.plist` に `NSHealthShareUsageDescription` 必須
- iOS は**どの項目を拒否されたかをアプリに教えない** (`authorizationStatus` は `.notDetermined` / `.sharingAuthorized` だけ)
- 拒否を検知したい場合 → 「データを query して 1 件も返ってこなければ拒否の可能性」というロジックでフォールバック

## Why
- Apple HealthKit 自体は強力だが、Capacitor 経由だと「JS から呼べるサーフェス」と「ネイティブ実装が必須な機能」の境界がプラグインの実装範囲で決まる
- 背景配信は OS の「アプリを wake up」設計に依存するため、JS layer だけで完結しない

## How to apply
- 新規アプリは **`@capgo/capacitor-health` を採用**。Capacitor v8 系で組む
- バックグラウンド読み取りが MUST なら、最初からネイティブ plugin 自作も視野に入れる (見積もりに+1週間)
- 「今朝の睡眠を朝のリマインダーに反映」は Watch 装着前提なら現実的、iPhone 単体だと精度低 (ステージ取れない) と割り切る
- 起床時 push 通知のトリガは「HealthKit データ着信」ではなく、ユーザー設定の固定時刻 → アプリ起動時に query が現実的
