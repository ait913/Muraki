---
title: LLM 生成 Push 通知の現実的アーキテクチャ (iOS APNs + Claude Haiku)
category: pattern
tags: [push-notification, apns, ios, llm, claude-haiku, latency-budget]
created: 2026-05-11
project: global
sources:
  - https://developer.apple.com/documentation/usernotifications
  - https://www.sleepfoundation.org/insomnia/treatment/cognitive-behavioral-therapy-insomnia
  - https://www.risescience.com/
  - https://www.anthropic.com/pricing
---

## Context
「起床コーチ」「就寝リマインド」「夜の振り返り誘導」など、AI が文面を個別生成する push 通知を iOS に飛ばす場面。レイテンシ・コスト・UX の現実的トレードオフ。

## What

### アーキテクチャ選択肢
| 方式 | 生成タイミング | 用途 |
|---|---|---|
| **Pre-generation** | 通知予定 15-30 分前にバッチで LLM を叩き、ペイロード確定 → APNs スケジュール | 起床アラーム代わり (ミリ秒精度必要) |
| **Just-in-time** | trigger 発火時に LLM → APNs (合計 3-8 秒) | 「振り返り誘導」など即時性低い通知 |
| **Hybrid** | 端末ローカル通知 (UNNotificationRequest) で時刻精度を担保 + 内容は事前生成 AI スロット | 起床通知の現実解 |

起床通知は **Hybrid が定石**。完全 server push は配信遅延 + iOS Focus mode の Notification Summary 埋没リスクがある。

### コスト試算 (Claude Haiku 4.5 想定)
- 1 通知 ~ 300 tokens 程度 (in + out)
- ~$0.0001 - $0.0003 / 通知
- MAU 1 万人 × 2 通知/日 = 月 ~$60-200 程度

1 人ユーザー (Touri 用) なら月数円。気にしなくていい。

### Template + AI slot hybrid のコピー設計
完全自由生成より、`[固定フレーム] + [AI が埋めるスロット]` が:
- ガバナンス (不適切表現の混入リスク低減)
- token 節約
- A/B test しやすい

例:
```
おはよう。{personalized_one_liner}
今日の予定は {first_event_summary} から。
```

### コピーライティング (CBT 原則)
- 「〜すべき」「早く起きて」は禁止 (達成できない時の罪悪感 → 離脱)
- 一人称 + 共感型: 「太陽の光が強いみたい。少しだけカーテン開けてみる?」
- 朝が辛いユーザーには **アイデンティティ肯定**: 「朝の静寂を独り占めできる時間まで、あと 5 分」

### iOS の通知挙動
- **Time-Sensitive Notifications**: 起床・就寝コーチは時間的緊急性ありとして entitlement 取得可能。Focus mode を貫通
- ただし頻度が高いと OS が「通知オフにしますか?」と提案する
- **Critical Alerts**: Apple の事前承認必要。睡眠アプリで取得は通常困難 (医療機器級用途のみ)
- iOS の **Notification Summary** に埋もれないよう重要度 metadata を付ける

### 通知タップ → アプリ起動 → 対話の遷移
- `userInfo` に `session_id` + `context_snippet` を入れる
- アプリ起動後、AI チャットの **最初の発言として通知文をそのまま再表示** → 思考の断絶を防ぐ
- 朝の対話は **1-3 ターン限界** (睡眠慣性)。3 ターン目で「今日の小さなアクション」を提示してクローズ

## Why
- 完全 server-push は数秒遅延 + APNs 配信揺らぎで「時刻精度」が必要なアラーム代わりにならない
- 一方、毎日 LLM 呼ぶコストは個人用アプリでは無視できる程度
- iOS Notification Summary は AI 通知を「重要でない」と誤判定する事例あり

## How to apply
Phase 1 (Touri 1 人) で採る方針:
- 起床通知: **ローカル時刻トリガー + 事前生成 (前夜 22:00 のジョブ) AI ペイロード**
- 就寝リマインド: just-in-time でも OK (時刻精度要らない)
- 夜の振り返り誘導: just-in-time。タップ → 対話起動
- 文面: Template + AI slot。slot は Haiku で 1-2 文生成
- Time-Sensitive entitlement は取る (Focus 貫通必要)
- Critical Alerts は申請しない (却下確率高い + 必要性も低い)
