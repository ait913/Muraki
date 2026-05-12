---
title: LLM Ready な気分ログのスキーマと UX (Daylio / How We Feel / Finch 系)
category: pattern
tags: [mood-log, schema, ux, llm, mental-health]
created: 2026-05-11
project: global
sources:
  - https://daylio.net/
  - https://howwefeel.org/
  - https://finchcare.com/
  - https://www.who.int/publications/i/item/PHQ-9
---

## Context
気分ログ / 感情記録 / journaling 系アプリの構造化スキーマを設計するとき、後段で LLM (Claude 等) が読みやすい形にする方法。Daylio / How We Feel / Finch / Reflectly の 2025-2026 構成を整理。

## What

### 気分尺度のモデル選択
| モデル | 軸 | 例 | 向き |
|---|---|---|---|
| Likert (1次元) | 1-5 段階 | Daylio, Reflectly | 摩擦最小・初期ユーザー |
| Circumplex (2次元) | Valence × Arousal | How We Feel | LLM 解析・パターン抽出 |

`Valence (快-不快) × Arousal (覚醒-非覚醒)` の 2 軸モデル (Russell 1980) は LLM が「燃え尽き予兆」や「焦燥」を検出しやすい。1 次元と併存させると入力 UX を保ちつつ豊富なデータが取れる。

### LLM-Ready なエントリ JSON
```json
{
  "entry_id": "uuid",
  "ts": "ISO8601",
  "mood": {
    "score": 4,             // 1-5
    "valence": 0.8,         // -1.0 .. 1.0
    "arousal": -0.2,        // -1.0 .. 1.0
    "label": "contented"
  },
  "tags": ["work", "social", "exercise"],  // semantic id 推奨
  "note": "free text",
  "context": { "weather": "sunny", "location": "home" }
}
```

ポイント:
- tag は `id: 101` ではなく `id: "social_isolation"` のような **semantic name**。Claude が読むだけで意味が分かる
- `correlations` 等の派生フィールドは on-the-fly で計算するか、weekly digest 時に固める

### 摩擦最小 UX (Daylio が確立した 3 タップルール)
1. 気分選択 (1 画面)
2. 活動タグ選択 (1 画面)
3. 保存

Quick log と Detail log (AI 対話で深掘り) を **トグル切替**。通知 / Widget / Watch face からの 1 タップ記録経路を別途用意。

### 継続性: Streak vs Weekly Insight
- 短期: Streak / gamification (Finch) は有効
- 長期: AI の **Weekly Insight** (週次レポート) のほうが内発的動機を作る
- 両方やる場合、Streak は「軽い記録」、Insight は「深い振り返り」で役割分担

### 臨床尺度 (PHQ-9 / GAD-7) の組み込み
- PHQ-9 (うつ): **2 週に 1 回**
- GAD-7 (不安): 週 1 〜 月 1
- 9 問を一気にではなく、通常のログフローに**マイクロサーベイ形式で 1-2 問ずつ**埋め込む
- 必須: 「これは診断ではない」免責 + 高スコア時の相談窓口リンク
- LLM 側に直近イベント (失恋・多忙) を context として渡すと false alarm 減

## Why
- LLM が読みやすい schema = 後で AI 秘書として価値を出せる土台
- 2 軸モデルは tag だけでは取れない「鬱状態 vs 焦燥状態」を区別できる
- 3 タップ以下でないと記録が続かない (Daylio が実証)
- 臨床尺度を入れると「気のせい」を客観化できるが、過剰検知のリスクがある

## How to apply
- DB 設計時に **Likert + Circumplex 両方** を必須カラムに入れる (片方は省略可能でも、後で 2 軸計算するには両方欲しい)
- tag は enum ではなく **semantic string id** + 多言語 label を別テーブル
- Quick log 経路を最初から設計に入れる (後付けは UX が崩れる)
- Weekly digest を LLM に作らせる場合、入力 token を節約するために **日次 summary JSON を事前に保存** し、week 単位ではそれを束ねる (生ログを 7 日分送らない)
- PHQ-9 は Phase 2 以降で良い。Phase 1 は気分尺度 + tag + 自由記述で十分
