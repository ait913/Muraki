---
title: 月次定期ルールを未確定 record として materialize する家計簿パターン (RRULE不採用・lazy補充)
category: pattern
tags: [recurring, materialize, finance, budget, drizzle, sqlite, forecast, balance, uniform-shape]
created: 2026-06-08
project: kinketsu-taisaku
sources:
  - Muraki/projects/kinketsu-taisaku/.designs/20260608-mvp-core.md §5
  - Muraki/projects/_pre/research-moneylog-successor-20260608.md B-2
  - Muraki/knowledge/pattern/rrule-string-onfly-expand-with-overrides.md (対比)
  - Muraki/knowledge/pattern/calendar-week-pattern-meeting-expansion.md (判断軸)
---

## Context

サブスク/クレカ/給料のような「毎月固定日・固定額の収支」を扱う家計簿で、定期収支を未来へ展開して残高着地予測に効かせたい場面。カレンダー系 (会議/シフト) とは要件が違う:

- FREQ=MONTHLY 単一バリエーション (週次/BYDAY/外部 .ics 互換 不要)
- 件数小 (1ユーザー数十ルール)・展開範囲有界 (現在〜十数ヶ月)・ルール編集稀
- 「予測」が core 機能 = 未確定(予定)を残高計算に混ぜる

## What

定期ルールを RRULE でも on-the-fly 展開でもなく、**未確定 record (paid=false) として record テーブルに materialize (実体 INSERT)** する。

### スキーマの要点
- `recurring_rule { dayOfMonth(1-31), signedAmount, categoryId, tagId, description, startMonth, endMonth?, active }`。RRULE 文字列は持たない。
- `record { ..., paid(bool), sourceRuleId(nullable FK), isManuallyEdited(bool) }`。
- **`unique(sourceRuleId, yearMonth)`** で二重生成防止 (SQLite は NULL を unique 衝突させないので手動 record は自由)。
- 端日は `clampDay(yearMonth, dayOfMonth) = min(dayOfMonth, daysInMonth)` で月末クランプ (31日→2月は28/29)。rrule npm 不要、date-fns 1 関数。

### 再生成 (re-materialize) の 3 値保護
ルール編集/補充時、`(ruleId, yearMonth)` の既存 record を:
- `paid=true` (確定済み) → 触らない
- `paid=false AND isManuallyEdited=true` (手動編集済み予定) → 触らない
- `paid=false AND isManuallyEdited=false` (素の予定) → 削除して再生成

過去月 (< currentMonth) は一切触らない (履歴保持)。手動編集は `PATCH record` で `sourceRuleId!=null` を編集したら `isManuallyEdited=true` を立てて以後保護。

### トリガー = lazy (cron 不採用)
書き込み時 (rule 作成/編集/settings変更) + **アクセス時 rolling 補充** (requireAuth 後の冪等フックで現在月〜現在月+N を埋める)。単一/少人数ユーザーの個人アプリでは cron インフラを持つ運用コストに見合わず、materialize は冪等・軽量 (存在確認は index hit) なので lazy で足りる。アクセスしない期間に古くても、見るときに補充される。

## Why

- **uniform shape**: 予測計算が「record を月ごとに Σ signedAmount」するだけで定期/手動を区別しない (moneylog の「record を積む」一元モデルに合致)。on-the-fly だと予測のたびにルール展開 + 手動 record マージの分岐を抱える。
- **override が只**: 「今月の給料だけ金額変更」が生成済み record の直接編集で済む。calendar 系の occurrence-override 別テーブルが要らない。
- **繰り越し残高が素直**: 未来各月に record が実在 → `月末残高[N]=月末残高[N-1]+月N収支` を confirmed/forecast 2 系列で累積するだけ。

## How to apply

- カレンダー系で on-the-fly/RRULE を選ぶのは「無限繰り返し・編集多発・外部同期」のとき (→ [[pattern/rrule-string-onfly-expand-with-overrides]] [[pattern/calendar-week-pattern-meeting-expansion]])。家計の定期支払いはどれも当てはまらない → materialize。
- ユニーク制約 `(sourceRuleId, yearMonth)` と「未確定&未編集のみ再生成」を必ずペアで設計する。これが無いと rolling 補充の冪等性が壊れる (毎アクセス重複生成 or 手動編集破壊)。
- 符号強制は record に `type` enum を作らず、書き込み時に backend が符号を確定 (収入カテゴリは+強制/支出は−強制/その他free)。type は signedAmount から導出する派生値。category 側に `signMode` 列を持たせると id 値非依存になりマルチユーザーで壊れない。
- 削除 semantics は `keepRecords` で 2 択: 既定 true (未確定未編集の予定のみ削除、確定/編集済みは sourceRuleId=null で切り離し保持) / false (全削除)。
