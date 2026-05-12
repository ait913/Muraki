---
title: iOS ハイブリッドアプリの push 通知スケジューリング (Local + APNs 併用)
category: pattern
tags: [ios, push-notification, apns, capacitor, scheduling]
created: 2026-05-11
project: global
sources:
  - https://capacitorjs.com/docs/apis/local-notifications
  - https://capacitorjs.com/docs/apis/push-notifications
  - https://developer.apple.com/documentation/backgroundtasks
---

## Context
「毎日特定時刻 (起床・就寝・服薬) に通知」「+ AI 生成のチェックインを動的に push」両方が必要な iOS アプリで採用する設計。Capacitor / Expo / React Native いずれでも適用可能。

## What
**Split Architecture (2026 標準)**:

| 用途 | 方式 | 理由 |
|---|---|---|
| 起床/就寝/服薬等の固定スケジュール | **Local Notifications** | オフライン動作、network 不要、システム精度高 |
| AI 生成チェックイン / 動的イベント | **Remote APNs** | サーバ主導で柔軟、リアルタイム |

**Local Notifications の制約と挙動**:
- iOS の pending 上限 = **64 件** (システム固定)
- 「毎日繰り返し」は 1 件としてカウント → 起床/就寝 2 件で済む
- アプリが killed / 端末 lock でも発火する
- スケジュール更新は **app foreground 時のみ可能** → `cancel()` → 新スケジュール `schedule()`
- iOS 17+: provisional auth (静か通知でプロンプト無し開始) と Apple Intelligence による summary バンドル化に注意

**Remote APNs (2026)**:
- 必須: APNs Auth Key `.p8` (cert 方式は実質廃止)、Key ID (10字)、Team ID、Bundle ID、App ID に Push Capability
- スケジューラ: サーバで cron / Redis-based queue / EventBridge 等から user の local time に APNs 叩く
- Node ライブラリ: `node-apn` (ESM 対応)、または `firebase-admin` で FCM 経由 (p8 handshake を吸収)
- iOS 19 以降は Deep Focus / Apple Intelligence 判定で配信遅延あり → high-priority App Intent 付与で回避

**Background scheduling (iOS の現実)**:
- BGAppRefreshTask は最大 30 秒、OS 学習で不定期実行
- 48 時間以上アプリを開かないと background task が止まる可能性
- → **background でのスケジュール再構築は信用しない**
- 代わりに「foreground 時に **次の 7-14 日分の local notification を先行スケジュール**」する戦略が定石

## Why
- Local 単独だと AI 生成のような動的通知が不可能
- APNs 単独だと network 死亡時に起床通知が飛ばない (生活リズム改善アプリでは致命的)
- Background 再スケジュールは iOS の仕様上信頼できない → 静的に先行登録するしかない

## How to apply
- アプリ起動時 / 設定変更時に「今後 14 日分の local notification」を一括登録 (起床+就寝で 28 件、上限 64 に余裕)
- ユーザーが起床/就寝時刻を変更したら全 cancel → 再登録
- AI チェックインや動的通知はサーバ → APNs ルート
- バックエンドが Node + Hono 系なら `node-apn` 直接利用、Firebase 入れたくないなら p8 自前管理
- 設計 doc には「Local + Remote 併用」「foreground 先行登録 14 日分」「上限 64 件設計」を明記
