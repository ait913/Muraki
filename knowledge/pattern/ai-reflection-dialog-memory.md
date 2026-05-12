---
title: AI 振り返り対話のセッション設計と階層型メモリ
category: pattern
tags: [reflection, dialog, memory, rag, llm, claude]
created: 2026-05-11
project: global
sources:
  - https://www.nngroup.com/articles/chatbots/
  - https://mindsera.com/
  - https://www.rosebud.app/
  - https://jamesclear.com/habit-stacking
---

## Context
夜の振り返り (evening reflection) を AI と対話で行う UX。Stoic / Rosebud / Mindsera の 2025-2026 設計と、長期運用での memory アーキテクチャ。

## What

### セッション設計
- **長さ**: 3-5 ターンが satisfaction × cognitive load のスイートスポット (NNG)
- これ以上長いと習慣化を阻害
- **形式**: 構造化プロンプト → 自由対話のハイブリッドが主流
  - 例 (Stoic): 「3 つの定型質問 → 最後だけ自由対話で AI が深掘り」

### Reflection フレームワーク選択肢
| フレームワーク | 内容 | 向き |
|---|---|---|
| Seligman 3 Good Things | 今日良かったこと 3 つ | ポジティブ心理学・継続性 |
| Stoic Evening Review | 何が正しく / 悪く / 明日どう改善 | 自己改善志向 |
| GROW | Goal / Reality / Options / Will | コーチング志向 (Mindsera) |
| Bullet Journal Daily Log | 出来事 / タスク / メモを分類 | 記録志向 |

tomori 用途 (生活リズム改善 + 秘書) なら **3 Good Things + Stoic 3 段の混合** が無難。GROW は重い。

### 保存形式: 双方向 (raw + structured)
1. **Raw transcript**: ユーザーの生発話。あとで自分が読み返す用 + 法的記録
2. **Structured summary (JSON)**: LLM が末尾で生成する圧縮データ

```json
{
  "date": "2026-05-11",
  "sentiment_score": 0.85,
  "top_emotions": ["accomplished", "calm"],
  "key_events": ["Backend refactoring done", "Coffee with Ken"],
  "insights": "Values deep work, watch caffeine.",
  "unresolved_concerns": "Friday presentation",
  "action_item_tomorrow": "Prepare 3 slides"
}
```

このサマリーは ~150 token 以内。「セッション末尾で AI に書かせる」ようプロンプトで指示。

### 階層型メモリ (Hierarchical Summarization)
| 層 | 内容 | 渡し方 |
|---|---|---|
| Short (3-7 日) | 生ログそのまま | 毎セッションのコンテキストに入れる |
| Mid (週 / 月) | 日次 JSON summary を束ねたもの | weekly digest 生成時に使う |
| Long (月超) | テーマ別 embedding + RAG | 「仕事の悩み」等のキーワードで類似引き |

これで token cost を抑えつつ「昨日の続き」も「3 か月前の悩み」も AI が思い出せる。

### トリガー設計
- **能動的 push**: 就寝 1 時間前 (default mode network 切替期)
- **Habit stacking**: 既存の習慣 (歯磨き / パジャマ着替え) と結合
- スクリーンタイム禁忌の問題: **VUI (音声のみモード)** の検討。画面見ずに完結

### 起動 → 対話 → クローズの流れ
1. Push 通知 (AI の問いかけが本文)
2. タップ → 通知本文を AI の最初の発言として表示
3. 3-5 ターン
4. AI が「今日のサマリー」を提示 → ユーザー確認 → JSON 保存
5. 「おやすみ」で明示クローズ

## Why
- 3-5 ターン制約: 反芻 (rumination) リスク + 習慣化に必要な低負担
- 階層メモリ: 全部 LLM context に入れると数か月で破綻、RAG だけだと「昨日の話」を忘れる
- 双方向保存: 構造化だけだと感情の機微が消える、raw だけだと AI が読みにくい
- 末尾サマリー: 翌日 AI が読み込む input を最小化できる

## How to apply
実装テンプレ:
- セッション state: `{ turns: [], framework: 'three_good_things', max_turns: 5 }`
- ターン上限到達で AI に「クロージング & サマリー生成」プロンプトを切替
- summary JSON はデイリーログテーブルに保存、別途 raw transcript は append-only
- weekly digest は cron で土曜夜 → 月曜朝の push に流す
- 朝の対話と夜の対話で別 system prompt (朝 = エネルギー喚起 / 夜 = 整理 + 慰労)
