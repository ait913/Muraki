---
title: GitHub OAuth App (classic) の callback URL は 1 本のみ — redirect_uri はサブディレクトリ一致で分岐可
category: library
project: global
tags: [github, oauth, callback, redirect-uri, oauth-app, github-app]
created: 2026-07-05
sources:
  - https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps
  - https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/about-the-user-authorization-callback-url
  - https://github.com/orgs/community/discussions/4238
---

## Context

1 つの GitHub OAuth App (classic) を「MCP 認証の federate 先」と「Web ダッシュボードのログイン」の両方で使いたい場面 (dandan-app stateful 転換)。

## What

- **OAuth App (classic) は Authorization callback URL を 1 つしか登録できない** (登録フォームに単一フィールドのみ)。GitHub App は最大 10 個登録可 — この差は 2026 年現在も変わらず。
- ただし `redirect_uri` パラメータは登録 callback URL と**完全一致でなくてよい**。公式ルール (Authorizing OAuth apps → Redirect URLs):
  - host (サブドメイン除く) と port は完全一致必須。**サブドメインは許容** (`oauth.example.com/path` OK)
  - **path は登録 callback URL のサブディレクトリなら許容** (`/path/subdir/other` OK、`/bar` NG)
  - loopback (`127.0.0.1` / `::1`) は port 違い許容。`localhost` より IP 推奨
- よって同一ドメインで用途を分けるなら:
  1. **callback 1 本 + state でルーティング分岐** (署名付き state に flow 種別を載せて callback handler で振り分け) — 最も一般的
  2. 登録 callback を親 path (例 `/auth/github`) にし、`redirect_uri` をサブパスで出し分け (`/auth/github/mcp` vs `/auth/github/dashboard`)
- 別ドメイン (別サブドメインでない別ホスト) に分けたい場合のみ OAuth App 2 個目が必要。

## Why

GitHub は OAuth App のマルチ callback 要望 (community discussion #4238) を GitHub App 側でのみ解決した。classic OAuth App は single-callback のまま据え置き。

## How to apply

- 同一サーバー同居 (MCP AS + dashboard) なら OAuth App は 1 個で足りる。state 分岐が既存コード (署名 state JWT) と親和的。
- 登録 callback を深い path (`.../callback`) にしてしまうと、サブパス分岐の余地が `/callback/*` 配下に限られる点だけ注意。
