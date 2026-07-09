---
title: MCP Apps (io.modelcontextprotocol/ui) の仕様現状とホスト描画マトリクス (2026-07)
category: library
project: global
tags: [mcp, mcp-apps, ext-apps, iframe, ui, claude, chatgpt, remote-mcp]
created: 2026-07-07
sources:
  - https://blog.modelcontextprotocol.io/posts/2026-01-26-mcp-apps/
  - https://modelcontextprotocol.io/extensions/apps/overview
  - https://modelcontextprotocol.io/extensions/client-matrix
  - https://github.com/modelcontextprotocol/ext-apps/blob/main/specification/2026-01-26/apps.mdx
  - https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/
  - https://github.com/modelcontextprotocol/ext-apps/issues/671
  - https://github.com/anthropics/claude-ai-mcp/issues/165
---

## Context

dandan-app 再設計で MCP Apps (iframe UI) をメイン機能に据える方針の前提確認。「どの実ホストで描画されるか」が土台。

## What

### 仕様 (2026-07 時点)
- MCP Apps = 初の公式 MCP 拡張。ID `io.modelcontextprotocol/ui`、仕様バージョン **2026-01-26、ステータス Stable**。2026-07-28 コア仕様 RC でも**拡張のまま** (コア統合されない)。
- 建て付けは不変: `ui://` リソース + tool `_meta.ui.resourceUri` (**ネスト形式が正**。flat `_meta["ui/resourceUri"]` は deprecated、GA 前に削除予定) + postMessage JSON-RPC (`ui/initialize` → `ui/notifications/initialized`、`ui/message`、`ui/update-model-context` 等)。
- **ホストは `resources/read` (MCP セッション内) で ui:// を取得 (MUST)** → OAuth 保護リモート MCP でも通常の Bearer 認証がそのまま適用され、UI 取得に別経路の認証は不要。外部アセットのみ `_meta.ui.csp` の origin から素の HTTPS fetch。
- transport (stdio/remote) による仕様上の差異は無し。Web ホストは double-iframe sandbox 必須 (ホスト側実装事項)。

### ホスト描画マトリクス (2026-07 上旬)
| ホスト | 公称 | 実態 |
|---|---|---|
| claude.ai (web) | 対応 | ★ **カスタムコネクタでは iframe が mount せず text-only** の報告が未解決 (claude-ai-mcp#165、2026-07-04 コメント: Max プラン + spec 準拠リモートで再現、「directory 掲載コネクタは描画・カスタムは非描画」が複数報告と整合。directory ゲートか?の公式回答なし) |
| Claude Desktop | 対応 | ★ 非描画バグ継続 (ext-apps#671 open、2026-07-06 時点も活動あり / #165: 1.12603.1 (2026-06-11 build) で stdio・remote 両方再現)。**天野 README の既知バグは未解消** |
| Claude iOS | 記載なし | 非描画報告あり (#165、2026-06-03) |
| Claude Code (CLI/VS Code/desktop/web) | **マトリクスに無い = 非対応** | 対応の公式言及ゼロ |
| ChatGPT | 対応 (公式マトリクス) | **Developer mode のカスタムコネクタで実描画を dandan-mcp が実機確認済み (2026-06)**。現状もっとも確実 |
| Codex (CLI/IDE/Web) | マトリクスに無い | 対応言及なし。Codex App changelog に「MCP app sizing」修正の記述があり将来対応の兆しはあるが不明 (出典弱: releasebot 要約) |
| その他対応 | VS Code GitHub Copilot / Microsoft 365 Copilot / Goose / Postman / MCPJam / Cursor / Archestra / PostHog Code (公式マトリクス) | basic-host (ext-apps 公式ハーネス) は開発検証用に確実 |

### OpenAI Apps SDK との関係
Apps SDK と MCP-UI が「先行者」で、その収斂として MCP Apps 標準が策定された (公式ブログ)。ChatGPT は標準 `io.modelcontextprotocol/ui` を描画する (公式マトリクス掲載)。

## Why

公式マトリクスの「対応」と実ホストの挙動が乖離している (Claude 系)。設計判断はマトリクスでなく open issue + 実機確認ベースで行う必要がある。

## How to apply

- **Claude 系ホスト (claude.ai / Desktop) のカスタムコネクタで iframe UI が出る前提の設計は 2026-07 時点では成立しない**。directory 掲載 (審査) が唯一の公称経路だが、カスタムコネクタ描画のタイムラインは公式回答なし。
- iframe UI の主戦場は **ChatGPT (developer mode カスタムコネクタ)**。Claude Code / Codex (チームの日常 agent ホスト) では UI は出ない → コア機能を iframe UI にゲートさせず、text/structured 出力で完結 + UI は progressive enhancement とするのが安全。
- OAuth 保護リモート MCP と MCP Apps の併用は仕様上問題なし (`resources/read` が認証セッション内)。
