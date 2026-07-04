---
title: リモートMCPのマルチテナント設計 — per-project URL バインド + 自前AS + 事実/判断の線引き
category: pattern
tags: [mcp, oauth, multi-tenant, rfc9728, rfc8707, github-app, go-sdk, floor-ceiling, agent-driven]
created: 2026-07-04
project: dandan-app
sources:
  - Muraki/projects/dandan-app/.designs/20260704-foundation.md
  - knowledge/library/remote-mcp-oauth-hosts-2026.md
---

## Context

クラウド上のリモート MCP サーバー（Claude Code / Codex から URL 追加 + OAuth）を、複数チーム・複数リポでマルチテナント運用したい。かつ「推論はホスト agent に委譲、サーバーは事実だけ持つ」構成（dandan-app）。同型の agent 駆動リモート MCP を設計する時の再利用パターン。

## What

### 1. テナント境界 = per-project MCP resource URL バインド
- MCP URL を `https://<base>/p/{project_id}/mcp` のように **project ごとに分ける**。
- OAuth の RFC8707 `resource` param = その project URL。発行トークンの audience をその URL に固定。
- Bearer verifier で「リクエスト URL の resource == トークンの resource」を検証 → 他テナント越境を transport 境界で遮断。
- **効果: MCP ツール引数から `project_id`/`owner`/`repo` を全廃できる**（URL バインドで暗黙化）。各ツールで越境チェックを書かずに済む。

### 2. 自前 Authorization Server（token passthrough 禁止の実装形）
- MCP server = OAuth2.1 Resource Server（go-sdk `auth.RequireBearerToken` + `ProtectedResourceMetadataHandler`）。
- 自前 AS を同一バイナリに同居（`/oauth/authorize|token|register`, RFC9728/8414 well-known）。
- upstream（GitHub 等）へは identity 取得のためだけに federate し、**upstream トークンは client に渡さない・DB にも残さない**。使ったら破棄。
- GitHub は **App の installation token を on-demand 発行**（1h 短命）してサーバー内でのみ使用 → 保管不要 → envelope 暗号化テーブルが要らなくなる。
- 自前 AS トークンは **opaque + sha256 ハッシュ保管**（JWT stateless でなく）→ revoke とメンバーシップのライブ照合が効く。

### 3. 単一 Go プロセスに 3 ルート群を mount
- (A) MCP RS `/mcp` (B) 自前 AS `/oauth/*` (C) ダッシュボード `/api/*`+静的、を 1 つの `http.ServeMux` に載せる。すべて `http.Handler` なので分割の必然がない。Coolify では 1 app + 1 Postgres が最小運用。

### 4. 「床を上げ、天井は上げっぱなし」— 事実/判断の線引き
- **コード（床・決定論）**: 件数集計・集合演算・冪等・永続化・外部 API 呼び出し。正確/公平/監査可能であるべきものだけ。
- **モデル（天井なし・判断）**: 洗い出しの中身・「誰に合うか」等。サーバーはスコアや正解を出さず、**生の事実（材料）だけ返す**。
- サーバー側 LLM 呼び出しはモデル固定 = 天井。だから脳はホスト（agent）に置く。
- 判断をコードに焼き込むと（例: 種別重み×スキル重なりで適合スコア算出）、モデルが賢くなっても無改修で伸びない → アンチパターン。
- 観点テンプレ/プロンプトは **レンズ**にし、末尾に「これ以外の重要観点があれば自分で立てよ」と **headroom** を空ける。硬直チェックリストにしない。
- 抽出（plan）は**非破壊で再実行可能**にする（`supersedes_plan_id` で旧版を superseded 保持）。より良いモデルで回し直して過去分ごと改善できる。

### 5. 観点テンプレ配達 = ツール戻り値ステアリングが主・prompts は従
- Codex は MCP prompts を surface しない → prompts 一本化は Codex ユーザーに届かない。
- 起点ツール（例 `get_breakdown_rubric`）の**戻り値本文にテンプレ全文 + 手続き指示**を埋め、agent にローカル調査 → `submit_*` を実行させる。prompts は Claude Code の slash command 補助のみ。

## Why

- per-project URL バインドは、マルチテナント越境検証を「各ツール実装」から「transport + トークン audience」の 1 箇所に集約でき、ツール面が単純化する。
- 自前 AS + installation token on-demand は、spec の passthrough 禁止を満たしつつ GitHub トークン保管の攻撃面を消す。
- 事実/判断の線引きは、AI モデル更新の速度（我々の実装より速い）を製品品質にそのまま流し込むための構造。

## How to apply

- リモート MCP をマルチテナントにするなら、まず「テナント = URL path segment + トークン audience」に落とせるか検討する。落とせれば全ツールから tenant 引数が消える。
- go-sdk v1.6.1 の `auth` パッケージで RS を組み、AS は自前で薄く（authorize/token/register + 2 つの well-known）。
- 設計レビュー時のチェック: 「このロジックは事実か判断か？ 判断ならコードから剥がしてモデルに返せ」。テンプレには headroom を、抽出には再実行導線を必ず入れる。
