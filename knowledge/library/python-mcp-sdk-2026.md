---
title: 公式 Python MCP SDK (FastMCP) — hosted/stateful/認証の現行API (2026-07)
category: library
project: global
tags: [mcp, python, fastmcp, streamable-http, oauth, rfc9728, token-verifier, stateful, multi-tenant]
created: 2026-07-09
sources:
  - https://github.com/modelcontextprotocol/python-sdk (main=v2 pre-release / v1.x branch=stable)
  - https://pypi.org/project/mcp/
  - https://github.com/modelcontextprotocol/python-sdk/blob/v1.x/docs/authorization.md
  - https://github.com/modelcontextprotocol/python-sdk/blob/v1.x/docs/server.md
  - https://github.com/modelcontextprotocol/python-sdk/blob/v1.x/src/mcp/server/auth/middleware/auth_context.py
  - https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization
---

## Context

Python で hosted・stateful・マルチテナントなリモート MCP サーバー (per-member auth, join でセッション確立, claim/poll 系ツール) を組めるかの裏取り。既存 knowledge (remote-mcp-oauth-hosts-2026 / remote-mcp-multitenant-self-as) は **Go go-sdk 前提** で spec 面は流用できるが Python SDK 固有 API は未カバー — その穴埋め。

## What

### バージョンと FastMCP の位置づけ
- PyPI `mcp` stable = **1.28.1** (Python 3.10+)。高レベル API は **FastMCP** (`from mcp.server.fastmcp import FastMCP`)。tool 定義は `@mcp.tool()` デコレータ (型ヒント= JSON Schema、手書き schema 不要)。
- ★ `main` ブランチは既に **v2 pre-release (2.0.0b1)**。v2 は `FastMCP`→`MCPServer` (`from mcp.server import MCPServer`) に改名する大改修。**v2 stable は 2026-07-27 予定、新 spec 2026-07-28 と同時**。production はまだ **v1.x のみ推奨**。依存に `mcp>=1.27,<2` の上限固定を入れないと stable v2 到達時に破壊される。
- 別プロジェクト `jlowin/fastmcp` (PyPI `fastmcp` 3.4.4) は**公式 SDK とは別物**。公式取り込み版の呼称は v1=FastMCP / v2=MCPServer。新規は公式 `mcp` を使う。

### トランスポート
- **Streamable HTTP が現行推奨** (`mcp.run(transport="streamable-http")`、既定 mount = `/mcp`)。旧 HTTP+SSE (2エンドポイント方式) は deprecated。
- モード: `FastMCP("X")` = **stateful** (Mcp-Session-Id ヘッダで per-connection セッション persistence)、`FastMCP("X", stateless_http=True, json_response=True)` = **stateless (推奨・スケールしやすい)**。
- 複数クライアント同時接続 OK。Starlette に `mcp.streamable_http_app()` を `Mount` して複数 FastMCP を相乗り可 (lifespan で `mcp.session_manager.run()` を起動)。ブラウザクライアント向けは CORS で `expose_headers=["Mcp-Session-Id"]` 必須。

### 認証 (Resource Server)
- `mcp.server.auth` が OAuth 2.1 **RS** 実装。`TokenVerifier` プロトコル (`async def verify_token(token)->AccessToken|None`) を実装し `FastMCP(token_verifier=..., auth=AuthSettings(issuer_url, resource_server_url, required_scopes))` に渡す → **RFC 9728 Protected Resource Metadata を自動配信** (401+WWW-Authenticate で AS discovery)。spec は 2025-11-25 revision に追随。
- ★ ツール内で認証 identity を読む: `from mcp.server.auth.middleware.auth_context import get_access_token` → 現リクエストの `AccessToken` を contextvar 経由で返す。**identity は per-request の token 由来**で取れる (引数自己申告に頼らない要件をこれで満たせる)。token→user の対応は `verify_token` 実装側 (opaque token を自前 AS の DB で照合) で持つ。
- AS は spec 上同居/別体どちらも可。既存 knowledge の「自前 AS 同居 + upstream IdP へ identity のみ federate、upstream token は client/DB に残さない」パターン (self-as) が Python でもそのまま適用可能。

### セッション状態
- `Context` オブジェクトはツール引数に型注釈するだけで注入 (`ctx: Context`)。`ctx.session` (通知送信)、`ctx.request_context` (request_id / meta / lifespan_context)、`ctx.fastmcp` (設定)。
- ★ **lifespan_context は server-global** (全セッション共有。DB プール等の置き場)。**per-connection の任意アプリ状態を後続ツール呼び出しへ持ち越す first-class API は無い**。「join で identity/role を紐付け以降のツールで参照」は SDK の in-process セッションに載せず、**identity=token 由来 + role/presence=Postgres (identity キー)** で解決すべき。in-process セッションは multi-replica/再起動で消え、stateful streamable HTTP は Mcp-Session-Id のスティッキールーティングが要る。

### 通知 / ロングポール
- server→client 通知は可: `ctx.session.send_*` (resource_updated / tool_list_changed / prompt_list_changed / log / progress)。streamable HTTP の SSE チャネルで届く。
- ロングポール (ツールを新着まで block) は**アプリレベルで可能** — ツールは async 関数なので `asyncio.Event`/Postgres LISTEN-NOTIFY を await できる。ただし接続を開き続けるため **stateful + SSE (json_response=False) + スティッキールーティング**が要り、多数同時保持はスケール負荷。MVP は client 側 `get_messages` ポーリングが安全。

## Why

- 要件 (hosted/stateful/per-member auth/join セッション/claim/poll) は **v1.x FastMCP で全て実装可能**。ただし「stateful セッション」を SDK の in-process セッションに載せる設計は multi-node/再起動で壊れる → 状態は Postgres、identity は token 由来にするのが正。
- v2 + 新 spec が 2 週間内に landing する端境期。新規を v2 pre-release に載せると破壊的変更を追う羽目になる。

## How to apply

- 新規は `mcp>=1.27,<2` で v1.x FastMCP + Streamable HTTP。identity は `get_access_token()`、role/presence/claim は Postgres (楽観ロック= `UPDATE ... WHERE version=?`)。**stateless_http=True でも全要件を満たせる** (Coolify/複数レプリカ向き) — 唯一 in-process 保持が要るのは将来の wait_for_messages ロングポールだけで、それは後付け or client ポーリングで回避。
- lifespan で asyncpg プールを張り lifespan_context に置く (per-session と混同しない)。
- v2/新 spec (2026-07-28) は landing 後に別途調査してから移行判断。今固定してよい。
