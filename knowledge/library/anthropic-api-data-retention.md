---
title: Anthropic Claude API のデータ保持・学習利用ポリシー (2026年5月時点)
category: library
tags: [anthropic, llm, privacy, compliance]
created: 2026-05-11
project: global
sources:
  - https://platform.claude.com/docs/en/build-with-claude/api-and-data-retention
  - https://privacy.claude.com/en/articles/7996866-how-long-do-you-store-my-organization-s-data
  - https://privacy.claude.com/en/articles/8956058-i-have-a-zero-data-retention-agreement-with-anthropic-what-products-does-it-apply-to
---

## Context
個人ヘルスケア・メンタル系アプリで Claude API を使うとき、「ユーザーの会話を Anthropic 側にどれだけ残されるか」「学習に使われるか」を正確に知っておく必要がある。ZDR (Zero Data Retention) を契約しない、標準 commercial tier の API キーで使う前提。

## What
- **標準 commercial tier の API デフォルト保持: バックエンドで 30日以内に自動削除** (privacy.claude.com 公式 articles/7996866, 2026-03-16 時点)
  - 一部の Web 検索結果は 2025-09-14 に 30→7日に短縮されたと記述するが、公式 KB の最新版は 30日と明記
  - 設計上は **「30日以内に削除される」前提で動くのが安全**
- **学習には使用しない (デフォルト)**: 標準 API の inputs/outputs はモデル学習に使われない (`/build-with-claude/api-and-data-retention` の "Retained data is never used for model training without your express permission")
- **ZDR は qualifying Enterprise customers のみ**: 標準ティアでは契約不可。`/v1/messages` と `/v1/messages/count_tokens` は ZDR 対応エンドポイント、それ以外 (Batch, Files, Code execution, MCP connector など) は ZDR 対象外
- **HIPAA-ready は別建て**: BAA 締結で HIPAA readiness を有効化可能。ZDR がなくても HIPAA 対象データを扱える設計に変わった (以前は ZDR 必須だった)
- **使用ポリシー違反時は最大 2 年保持**: ZDR 契約があっても、Usage Policy 違反でフラグされた場合は 2 年まで残す可能性あり

### 機能別 ZDR eligible (重要なものだけ)
| 機能 | ZDR | 備考 |
|---|---|---|
| Messages API | Yes | 標準 |
| Token counting | Yes | |
| Prompt caching | Yes | KV cache は TTL 期限で削除 |
| Web search tool | Yes | dynamic filtering を除く |
| Batch processing | **No** | 29日保持 |
| Files API | **No** | 明示削除まで保持 |
| Code execution | **No** | コンテナ最大 30日 |
| MCP connector | **No** | 標準ポリシー |

## Why
- Anthropic は 2025-2026 にかけて API のデータ最小化を進めており、デフォルトで「prompts/outputs は学習に使わない・短期間で削除」を約束
- ただし「stateful な機能」(Batch, Files, Code execution) は仕組み上保持が必要なので個別の保持期間
- 個人ヘルスケアアプリのように「ログを取らないことを売りにする」場合、これらの ZDR 非対応機能を**設計の段階から避ける**のが筋

## How to apply
- 一般公開を見据えたアプリでは、利用者向けに「Anthropic に送信した内容は **最大 30日** Anthropic 側で保持される (削除予定)、学習には使われない」と明記
- Batch API / Files API / Code execution / MCP connector は使わない設計を選ぶ (これらを使うと保持期間が長くなる)
- ZDR が必要になったら Enterprise 契約 (Anthropic sales) を検討。標準 API キーでは申し込めない
- アプリ側で**送信前に PII マスキング**するレイヤを挟むのが追加防御
- DB に保存する会話履歴はアプリ層暗号化 (envelope encryption) する。Anthropic に送るときは平文だが、DB at-rest は守る
