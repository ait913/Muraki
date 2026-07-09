---
title: 公式 GitHub MCP server の認証設計と MCP write/inform 指針 (2026)
category: library
project: global
tags: [mcp, github, oauth, github-app, pat, tools-vs-resources, model-controlled, dandan]
created: 2026-07-05
sources:
  - https://github.com/github/github-mcp-server
  - https://github.blog/changelog/2025-09-04-remote-github-mcp-server-is-now-generally-available/
  - https://docs.github.com/en/copilot/how-tos/provide-context/use-mcp-in-your-ide/set-up-the-github-mcp-server
  - https://modelcontextprotocol.io/docs/concepts/tools
  - https://modelcontextprotocol.io/specification/2025-06-18/server/resources
  - https://github.com/atlassian/atlassian-mcp-server
  - https://linear.app/docs/mcp
  - https://mcp.sentry.dev/mcp
---

## Context

dandan (リモート MCP, GitHub App 認証, Issues R/W) の「書き込みを持つ意味・App install 摩擦の妥当性」を判断するため、公式 GitHub MCP と他社リモート MCP の認証・write設計を調査。

## What

### 公式 GitHub MCP server (github/github-mcp-server) の認証
- Remote 版 (github.com ホスト, 2025-09-04 GA) は **OAuth 2.1 + PKCE が主**。「no token to create or store」、 brに保持は in-memory のみ。PAT も header で併用可。first-party Copilot IDE + Cursor がネイティブ対応。
- Local 版 (Docker) は OAuth (公式イメージにアプリ資格情報同梱) / PAT (`GITHUB_PERSONAL_ACCESS_TOKEN`, OAuth より優先) / 自前 OAuth・GitHub App (GHE で必須)。
- ★ **per-repo の GitHub App install は要らない**。認証ユーザーの既存アクセス範囲 (token scope) をそのまま使う =「any repository you have access to」。個人リポは OAuth ログインだけで即使える。
- ★ 例外は **org 側の統制**: OAuth access policy 制限がある org は各 MCP host アプリの OAuth App 有効化が要る (VS Code / Visual Studio 除く)。org 管理者ポリシーで許可 scope/app が制限され得る。= install強制ではなく OAuth app approval モデル。
- write は server が持つ (issue/PR 作成等)。粒度制御は `--toolsets`(機能群) / `--tools`(個別) / `--read-only`(write スキップ) / OAuth scope 宣言 (`repo` 等)。

### 他社リモート MCP の認証パターン
- **Atlassian** (公式 remote): OAuth 2.1 or API token。Marketplace install 不要、**OAuth consent 完了時に just-in-time install** される。
- **Linear**: Streamable HTTP + OAuth 2.1 + DCR。Bearer/API key を Authorization header 直渡しも可 (read-only 制限 key あり)。
- **Sentry** (`mcp.sentry.dev/mcp`): OAuth Bearer + Sentry-Bearer (upstream に検証/保存せず forward するモード)。
- **Notion** (公式 remote): user-based OAuth 必須、bearer token 非対応。
- 総じて **OAuth (workspace/user 単位) が主流。per-resource の事前 install を要求する設計は少数** で、あっても JIT install (Atlassian) や org policy approval (GitHub) に留まる。

### MCP の write-vs-inform 設計指針 (公式)
- **tools = model-controlled** (LLM が文脈で自律的に発見・呼出、副作用あり得る)。**resources = application-controlled** (host が明示 fetch する read-only データ)。prompts = user-controlled。出典: modelcontextprotocol.io tools/resources 仕様。
- 副作用を伴う操作は tools として正当。ただし spec は「trust & safety のため常に human-in-the-loop で invocation を拒否できる **SHOULD**」「clients SHOULD: sensitive operation は confirmation、tool input をユーザーに提示」。
- ★ **「LLM がやれることを server で再実装するな」という明文の公式原則は見つからず (未確認)**。spec は write tool を許容・普及もしている (公式 GitHub MCP 自身が issue 作成 write を持つ)。write を server に持たせること自体は spec 上アンチパターンではない。

## Why

- 公式 GitHub MCP が per-repo App install を捨てて OAuth user-token scope に寄せているのは明確なシグナル: **「新リポで使う摩擦」を最小化する方向が業界標準**。App install は org 統制が要る場面の追加レイヤであって、既定の必須手続きではない。
- 一方 write を server に持たせること自体は否定されていない。公式 GitHub MCP も write tool を大量に持つ。論点は「write の有無」でなく「認証の摩擦 (App install) が価値に見合うか」。

## How to apply

- リモート MCP の認証は **OAuth user/workspace scope を第一候補**にし、per-resource install は「org 統制が必須」等の明確な理由がある時だけ足す。dandan の GitHub App per-repo install は、Issues R/W のためだけなら過剰摩擦の疑い。
- ただし GitHub App には OAuth user-token にない利点がある (bot identity / 短命 installation token / user 不在でも動く / fine-grained repo permission)。dandan がこれらを要件にするなら install は正当化される。要件を先に確定させる。
- write を持つか薄いアドバイザーかは spec 的にはどちらも可。判断軸は「認証摩擦 vs 提供価値」であって「write は再実装だから悪」ではない。
