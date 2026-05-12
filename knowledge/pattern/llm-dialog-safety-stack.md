---
title: LLM 対話アプリの安全境界スタック (regex 先行 + tool 強制 + AAD 暗号化)
category: pattern
tags: [llm, safety, crisis-detection, anthropic, tool-use, envelope-encryption, mental-health]
created: 2026-05-11
project: global
sources:
  - Muraki/knowledge/pattern/cbt-ai-companion-dialog.md
  - Muraki/knowledge/pattern/envelope-encryption-postgres-node.md
  - Muraki/projects/tomori/.designs/20260511-phase1-core.md
---

## Context

メンタルウェルネス / 生活リズム / AI 秘書系で LLM (Claude Haiku 4.5 等) と長時間対話する。
「危険発言を見逃さない」「LLM の構造化出力を信頼できる形で受ける」「DB に残るログを at-rest 暗号化する」を 1 セットで設計する必要がある。tomori Phase 1 で確立した重ね方。

## What

### Layer 1: regex 先行で LLM を呼ばずに crisis 検知

- ユーザー発話を **NFKC + lowerCase 正規化** してから regex 群にかける
- 1 つでも hit したら **LLM を呼ばない**。`crisis_events` に検知ログ (内容は保存しない、id と detector 種別のみ) + セッションを `close_reason='crisis'` でクローズ + ハードコード `CrisisCard` を返す
- 「LLM 任せの危険判定」は事故事例 (Character.ai 訴訟等) があるため必ず外す
- 正規表現は **`packages/safety/src/patterns.ts` のように single source** にまとめてテストで全件 hit/non-hit ペアを保証

### Layer 2: LLM 出力にも `[CRISIS_DETECTED_BY_MODEL]` センチネル

- system prompt に「危険な兆候を感じたら共感も推測も追加せず `[CRISIS_DETECTED_BY_MODEL]` とだけ最終出力」と仕込む
- assistant 発話にこのトークンが入っていたらサーバ側でも crisis 扱い (`detected_by='classifier'`)
- Layer 1 と OR 合成。両方使う

### Layer 3: 構造化サマリーは tool 強制 + 再試行 + fallback の 3 段

評価対話 (tomori の evening 等) の末尾で JSON サマリーを生成する場面:

1. tool 定義は **`strict: true` 必須** (Anthropic 2026 新機能)
2. 最終ターンで LLM が tool を呼ばなかったら、サーバが `tool_choice: { type: 'tool', name: 'save_summary' }` で **強制再呼出**
3. それでも schema 違反なら **最小サマリー fallback** (`{insights: '生成失敗', ...required fields}`) を保存

これで Reviewer のテストは「LLM が tool を呼ばないモック」「schema 違反モック」のそれぞれで `dialog_summaries` が必ず 1 件保存されることを保証できる。

### Layer 4: 送信前 maskPII を **1 関数に分離**

- `maskPII(text): string` を `packages/llm` の最上位 export として置く
- email / 電話 (JP) / Luhn-pass の CC 番号 を `[EMAIL]` / `[TEL]` / `[CC]` に置換
- **全角は対象外** と仕様化 (false negative の存在を明示)、テストで仕様として固定
- LLM に渡す前に **context 全体 + ユーザー発話の両方** に通す
- assistant 発話はマスクしない (LLM 生成物に PII は本質的に混ざらない)

### Layer 5: AAD に user_id を入れた AES-256-GCM

- `encrypt(dek, plaintext, aad)` の `aad = Buffer.from(user_id, 'utf8')`
- 別ユーザーの DEK で復号しようとすると auth tag 違反で死ぬ → ロジックバグで cross-user 漏洩を構造的に防ぐ
- Reviewer は「AAD を変えると decrypt が throw」を必須テストにする (tomori §7.9.3)

### Layer 6: 削除フローは DEK 物理削除を最優先

- `/api/account/delete` で `user_keys` を物理 DELETE → ON DELETE CASCADE で他テーブルも消える
- email は `deleted-<uuid>@tomori.local` に書き換え (列の UNIQUE 制約を壊さない)
- session は全 revoke
- これにより GDPR right-to-erasure 相当を低コスト実装

## Why

- LLM の「不適切な共感」が最大リスク (hallucination ではない)
- tool 強制 + fallback は LLM の確率的挙動に対する唯一の防衛線。3 段にしないと UX が崩れる (黒画面・無限ロード等)
- AAD を入れる慣習が無いと、user_id 取り違えバグが直接データ漏洩になる
- maskPII を 1 関数に分けると Reviewer のテスト網羅率が上がる。inline 実装だと網羅できない

## How to apply

1. 新規 LLM 対話アプリの設計 doc に **「6 レイヤすべて」を §挙動仕様に明文化**
2. Layer 1 の regex セットは言語別 (ja/en) に分けて配置、テストは ID で参照
3. Layer 3 の fallback サマリーは「最小スキーマで必須フィールド埋め」と仕様で固定する (`insights: '生成失敗'` 等)
4. Layer 4 の maskPII は idempotent でなくてよいが「既存マスクは破壊しない」は仕様化
5. Layer 5 で AAD を user_id 以外 (例: session_id) にすると、user 単位の長期復号で死ぬ。**user_id で統一**
6. Layer 6 の削除確認文字列は大文字 `'DELETE'` 固定、小文字は 400 にする (操作ミス防止)
7. crisis card のコンテンツは env (`*_CRISIS_HOTLINES_JSON`) で運用、コード変更なしで番号差し替え可能に
