---
title: Postgres + Node でのアプリ層 envelope encryption パターン (Coolify セルフホスト)
category: pattern
tags: [encryption, postgres, security, coolify, envelope-encryption]
created: 2026-05-11
project: global
sources:
  - https://github.com/47ng/prisma-field-encryption
  - https://platform.claude.com/docs/en/build-with-claude/api-and-data-retention
---

## Context
個人ヘルスケア / メンタル系アプリで「ログ取らない・コード公開可・at-rest 暗号化・LLM 処理時のみ in-memory 復号」を実装したい。バックエンドは Coolify (Docker) + Postgres、ソロ運用。

## What

### 鍵階層 (envelope encryption)
- **DEK (Data Encryption Key)**: ユーザーごと、Postgres の users/keys テーブルに **KEK で暗号化した状態で** 保存
- **KEK (Key Encryption Key)**: マスターキー、保管先を選ぶ

### KEK 保管先の選択肢 (Coolify セルフホスト前提)
| 方式 | 安全性 | 運用負荷 | 推奨度 |
|---|---|---|---|
| Coolify env var (平文) | 低: VPS root 奪取で露出 | 最低 | 初期 MVP 限定 |
| AWS KMS / GCP KMS | 高: VPS 物理奪取でも守れる | 低 (月 $1 程度) | ★ ソロ Dev には現実解 |
| HashiCorp Vault セルフホスト | 高 | 高 (もう 1 サーバ) | 不要なほどオーバー |
| age + SOPS + ファイルマウント | 中: ファイル管理 OK なら | 中 | Coolify UI と相性悪い |

→ **将来公開する想定なら最初から AWS KMS にしておくのが楽**。`@aws-sdk/client-kms` でアプリ起動時または DEK 生成時のみ呼び出し。

### 暗号化箇所: アプリ層 一択
- **pgcrypto は NG**: pgp_sym_encrypt のキーがクエリ文字列 → Postgres ログに残るリスク、DB 管理者がプレーンテキスト見える
- アプリ層で **AES-256-GCM (node:crypto)** または **XChaCha20-Poly1305 (@noble/ciphers / libsodium-wrappers)**
- DB は `bytea` として暗号文を保存

### スキーマ慣習
```sql
content      bytea NOT NULL,  -- ciphertext (nonce 別カラム推奨)
nonce        bytea NOT NULL,
dek_id       uuid NOT NULL,   -- どの DEK を使ったか
alg_version  smallint NOT NULL DEFAULT 1,
created_at   timestamptz NOT NULL  -- メタデータは平文
```
- メタデータ (timestamps, user_id, type) は平文 → 時系列クエリ・index が効く
- 検索が必要なフィールドは **Blind Index** (HMAC) を別カラムに

### 全文検索が要るとき
- pg_trgm / GIN は暗号文に使えない
- 解: client-side トライグラム分割 → HMAC → Bloom Filter として bytea/bit カラムに保存 → SQL のビット演算で絞り → アプリ側で復号して偽陽性除去
- 実装ライブラリ: CipherSweet (PHP オリジン、Node ポートあり) が代表

### ライブラリ評価 (2026-05)
| ライブラリ | 状態 | 採否 |
|---|---|---|
| **@noble/ciphers / node:crypto** | active | ★ 自作の基盤に最適 |
| **prisma-field-encryption** (47ng) | v1.6.0 (2024-09)、Prisma 4.7-6.13 対応、key rotation あり、AES-GCM-256 | 採用可、Prisma 使う場合 |
| sequelize-encrypted | 18ヶ月以上更新なし | 不採用 |
| typeorm-encrypted | 同上 | 不採用 |
| CipherSweet (node port) | active、Blind Index 同梱 | searchable encryption が要るなら |

### 鍵 rotation
- **KEK rotation**: KMS の自動 rotation。古い KEK でも DEK 復号可能なのでダウンタイムなし
- **DEK rotation**: 暗号文に `alg_version` / `dek_id` を埋めて lazy migration (アクセスされたら最新 DEK で再暗号化) または batch job

### LLM 境界
- Anthropic API には**平文を送る** (Bedrock/Vertex 経由なら別ポリシー)
- 標準 commercial tier は **デフォルト 30日以内に削除・学習に使わない** (knowledge/library/anthropic-api-data-retention.md)
- アプリ側で**送信前 PII マスキング**するレイヤを推奨
- 受信したレスポンスは DB に書く際に envelope encrypt

## Why
- セルフホスト VPS は AWS RDS 等のマネージド暗号化が使えない → アプリ層暗号化が現実解
- pgcrypto を使うとキーが SQL に流れる構造的問題があり、PostgreSQL コミュニティでも non-recommended
- envelope encryption は per-user DEK にすることで「特定ユーザーのデータ削除 = DEK 破棄」だけで実現可能 (GDPR right to erasure 対応が楽)
- LLM プロバイダ側に平文を送る瞬間は避けられないので、「**送信前に PII を削る + LLM プロバイダの ZDR 条件を確認**」の二段構え

## How to apply
1. MVP では Coolify env var で KEK を始めても良いが、コードは **KEK provider を抽象化** しておく (`getKEK(): Promise<Buffer>`) — 後で AWS KMS に差し替えやすい
2. DEK 生成は user 作成時 1 回、users_keys テーブルに保存
3. 暗号化は `@noble/ciphers` か `node:crypto` の AES-256-GCM をラップした薄い util を書く (テストしやすい)
4. Prisma を使うなら `prisma-field-encryption` を試す価値あり、ただし key rotation や custom KMS は自作 util の方が制御効く
5. 検索要件が出てきたら Blind Index → Bloom Filter の順で段階導入
6. LLM 送信前マスカ (`maskPII(text)`) を 1 関数として明示分離 → テストで網羅
