---
title: リモートMCPサーバー + OAuth のホスト対応と認可spec (2026)
category: library
project: global
tags: [mcp, oauth, claude-code, codex, streamable-http, go-sdk, rfc9728]
created: 2026-07-04
sources:
  - https://code.claude.com/docs/en/mcp
  - https://developers.openai.com/codex/mcp
  - https://developers.openai.com/codex/config-reference
  - https://modelcontextprotocol.io/specification/2025-06-18/basic/authorization
  - https://github.com/openai/codex/pull/4317
---

## Context

クラウド上のリモートMCPサーバーを Claude Code / Codex CLI (agent型ホスト) から URL 追加 + OAuth 認可で使わせる設計の前提確認。

## What

### Claude Code (remote MCP + OAuth)
- `claude mcp add --transport http <name> <url>` で remote MCP を追加。SSE (`--transport sse`) は deprecated、HTTP 推奨。
- OAuth 2.0 native 対応。401/403 で `/mcp` パネルに認可要フラグ → ブラウザで認可。v2.1.186+ は `claude mcp login <name>` でシェルから直接 OAuth フロー実行、`claude mcp logout` で失効。
- PKCE 使用・public client (client_secret 不要)。Dynamic Client Registration 対応。ヘッダ認証 (`--header "Authorization: Bearer .."`) も併用可。
- MCP prompts を `/mcp__<server>__<prompt>` の slash command として surface する (公式サポート)。`list_changed` で prompts/tools/resources を動的更新。

### Codex CLI (remote MCP + OAuth)
- 公式 docs 上は remote Streamable HTTP を標準サポート。`~/.codex/config.toml` に:
  ```toml
  [mcp_servers.example]
  url = "https://mcp.example.com/mcp"
  bearer_token_env_var = "TOKEN"          # optional
  http_headers = { "X-Foo" = "bar" }      # optional
  ```
- OAuth: `codex mcp login <server-name>` でブラウザフロー。`mcp_oauth_callback_port` / RFC 8707 resource param 対応。
- ★ 歴史的経緯: streamable HTTP は当初 PR #4317 で `experimental_use_rmcp_client` フラグ必須だった。現行 docs は標準機能として記載。**Codex の版によってフラグ要否が変わる** → 実機の codex バージョンで要確認。
- ★ prompts の slash command 化は Codex では**未サポート/検討中** (openai/codex issue #8342)。Codex 側は prompts を surface しない前提で設計すべき。

### MCP Authorization spec (2025-06-18 revision)
- Authorization は OPTIONAL だが、HTTP transport は本 spec に SHOULD 準拠。
- MCP サーバ = OAuth 2.1 **Resource Server**。Authorization Server は同居でも別entityでもよい (spec 範囲外)。
- MCP server **MUST** RFC 9728 Protected Resource Metadata 実装。401 に `WWW-Authenticate` ヘッダで metadata URL を示す。`/.well-known/oauth-protected-resource` に `authorization_servers` を返す。
- AS は RFC 8414 Authorization Server Metadata を **MUST** 提供。client は両方を使って discovery。
- client は PKCE **MUST**、RFC 8707 `resource` param **MUST** (authz+token 両方)。DCR (RFC 7591) は SHOULD。
- ★ upstream IdP 委譲 (GitHub OAuth に federate): spec 上「MCP server が upstream API に対し別の OAuth client として振る舞う」ことは想定済み。ただし **token passthrough は明確に禁止** — MCP client から受けた token を upstream にそのまま流すな。MCP server は自分の AS が発行した token のみ受理し、audience 検証必須。GitHub token は server 内部で別管理。confused deputy 対策で static client ID 使用時は動的登録 client ごとに user consent 必須。

### go-sdk v1.6.1 (実測: modcache 参照)
- `func (s *Server) AddPrompt(p *mcp.Prompt, h mcp.PromptHandler)` 存在。`PromptHandler = func(ctx, *GetPromptRequest) (*GetPromptResult, error)`。`RemovePrompts` もあり。
- `mcp/streamable_server.go` に StreamableHTTP サーバ実装あり。
- `auth` パッケージが spec 準拠の部品を提供: `RequireBearerToken(verifier TokenVerifier, opts)` middleware (401 + WWW-Authenticate 自動)、`ProtectedResourceMetadataHandler(metadata)` (RFC 9728)、`oauthex.ProtectedResourceMetadata` 型。→ 自前 Resource Server 実装の土台が揃っている。

## Why

agent型ホスト2種とも remote MCP + OAuth を成立させられる。ただし Codex は (a) 版によるフラグ要否 (b) prompts 非surface の2点で Claude Code と非対称。

## How to apply

- 観点テンプレの配達は **prompts に一本化しない**。Codex が prompts を出さないため、tool 戻り値ステアリング (tool の中でテンプレ文字列を返す) を主経路にし、prompts は Claude Code 向けの補助 UX とするのが安全。
- サーバは go-sdk `auth.RequireBearerToken` + `ProtectedResourceMetadataHandler` で Resource Server を組む。自前 AS を建てて GitHub OAuth へ federate、GitHub token はサーバ内部保管 (client に渡さない)。
