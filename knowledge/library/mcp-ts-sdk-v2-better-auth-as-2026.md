---
title: MCP TS SDK v2 は AS を捨てた — Next.js の自前 AS は better-auth の @better-auth/mcp で組む (2026-10 実測)
category: library
project: global
tags: [mcp, oauth, nextjs, better-auth, cimd, dcr, typescript-sdk-v2, claude-code]
created: 2026-10-02
sources:
  - https://github.com/modelcontextprotocol/typescript-sdk/blob/main/docs/migration/upgrade-to-v2.md
  - https://raw.githubusercontent.com/better-auth/better-auth/main/docs/content/docs/plugins/mcp.mdx
  - https://claude.com/docs/connectors/building/authentication
  - 実測 (wasawasa probe: Next 16.3.8 + better-auth 1.7.7 + @modelcontextprotocol/server 2.2.0 + 実 Postgres)
model-era: sonnet-5
---

## Context
Next.js (Route Handler) にリモート MCP + OAuth を同居させ、GitHub を upstream IdP にしたい。詳細・周辺 API は `projects/wasawasa/.knowledge/research-20261002-phase1.md`。

## What
- `@modelcontextprotocol/sdk` は 1.31.0 で保守モード。v2 stable (2026-07-27) は `@modelcontextprotocol/server` / `node` / `express` / `core` に分割。**AS ヘルパ (`mcpAuthRouter`, `ProxyOAuthServerProvider`, `OAuthServerProvider`) は v2 から削除** (`server-legacy/auth` に凍結コピー、「AS は専用 IdP/OAuth ライブラリへ」)。v1 の AS ヘルパは Express 前提で Route Handler に載らない。
- v2 の RS: `createMcpHandler(factory, opts)` → `handler.fetch(request, { authInfo })` (web 標準、stateless、`legacy` 既定で 2025 世代クライアントも受ける)。ツール内は `ctx.http?.authInfo`。
- AS は better-auth: `jwt()` + `mcp({loginPage, consentPage, resource})` + `cimd({fetchClientMetadataResource, metadataProfile:"mcp-2026-07-28"})`。`requireMcpAuth(auth, (req, claims) => handler.fetch(req, {authInfo}), {resource})` で JWT の `sub` を identity にできる (実測で通った)。
- Next 側に **`app/.well-known/oauth-protected-resource[/mcp]/route.ts` (`auth.handler(req)` 転送) と `app/.well-known/oauth-authorization-server/api/auth/route.ts` (`oauthProviderAuthServerMetadata(auth)`) が要る** (無いと PRM 404)。
- DCR で `application_type` 省略 + loopback http redirect は 400。Claude Code は CIMD (`https://claude.ai/oauth/claude-code-client-metadata`、ポート違い許容) で通る。Claude は AS metadata に `client_id_metadata_document_supported:true` かつ `token_endpoint_auth_methods_supported` に `none` がある時だけ CIMD を使う。
- `getUserInfo` で `null` を返すと GitHub 等のサインインを OAuth 完了前に拒否できる (Org 限定ログインの公式推奨位置)。

## Why
SDK 単体で AS を持てなくなったため、Python (FastMCP の AuthSettings + 自前 AS) に倒さなくても、better-auth が DCR/CIMD/PKCE/resource binding/refresh rotation を担う。

## How to apply
Next.js + MCP + OAuth は `@modelcontextprotocol/server@2` + better-auth で組む。`legacy: "reject"` は Claude.ai/Codex の世代が不明な間は付けない。`npx prisma` 等の無 pin と同様、`npm view <pkg> dist-tags` で CLI と client の `latest` が別物でないかを見る。
