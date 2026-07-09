---
title: リモートMCPのエージェント誘導サーフェス (server instructions / tool search / prompts / entry tool) 2026
category: library
project: dandan-app
tags: [mcp, claude-code, codex, server-instructions, tool-search, prompts, agent-ux]
created: 2026-07-07
sources:
  - https://code.claude.com/docs/en/mcp
  - https://developers.openai.com/codex/mcp
  - https://developers.openai.com/codex/changelog
  - https://github.com/github/github-mcp-server (pkg/inventory/instructions.go, pkg/github/toolset_instructions.go)
  - https://github.com/oraios/serena (CHANGELOG.md)
  - https://www.anthropic.com/engineering/writing-tools-for-agents
  - https://github.com/openai/codex/issues/8342
---

## Context

多ツール (20+) のリモート MCP サーバーで「エージェントにどのツールから始めるか・ワークフローをどう運ばせるか」を設計する場面。ホストは Claude Code / Codex CLI。

## What

### 両ホスト共通で効く唯一のチャネル = MCP `instructions` フィールド
- Claude Code: tool search が**デフォルト有効** — セッション開始時にロードされるのは「ツール名 + server instructions」のみ。ツール定義 (description 含む) は ToolSearch で必要時に遅延ロード。server instructions が「いつこのサーバーのツールを探すか」を教える主役 (公式が明言、skills に類する扱い)。
- Claude Code は **tool description / server instructions を各 2KB で truncate**。重要事項は先頭に。
- Codex: 「Codex reads the MCP `instructions` field returned during initialization and uses it as server-wide guidance alongside the server's tools」(公式 docs)。かつ Codex CLI 0.142.2 (2026-06-25) で「MCP tools now use tool search by default when supported」— Codex 側もツール定義は遅延化。
- → 「まずどのツールを呼ぶか」の知識をツールの戻り値の中にだけ置くのは鶏卵になる。**server instructions に置けば両ホストで初期コンテキストに入る**。
- go-sdk v1.6.1: `mcp.ServerOptions.Instructions string` で設定可 (server.go:62)。

### prompts の非対称 (2026-07 時点も継続)
- Claude Code: `/mcp__<server>__<prompt>` で surface。引数はスペース区切り (`/mcp__jira__create_issue "Bug in login flow" high`)。結果は会話に直接注入。`prompts/list_changed` 対応。
- Codex: prompts 非 surface のまま。openai/codex issue #8342 (2025-12 起票) は open・公式返答なし・changelog にも prompts エントリなし (2026-07-07 確認)。

### 実サーバーの定石
- **GitHub 公式 MCP** (github/github-mcp-server): server instructions を**コード生成** (`pkg/inventory/instructions.go` + `pkg/github/toolset_instructions.go`)。base instruction に list_* vs search_* の使い分け・pagination 指針、toolset ごとに「Always call 'get_me' first to understand current user permissions and context」「Use 'search_issues' before creating new issues」「Check 'list_issue_types' first」等の **call-X-first 誘導を instructions 側に集約**。有効 toolset に応じて動的合成。ツール群は toolsets (default: context, repos, issues, pull_requests, users) で絞る。
- **Serena** (oraios/serena): 段階開示 — 接続時は 1 文の bootstrap prompt のみ、フル説明は `initial_instructions` ツールで on-demand (「keeping the initial context lean」)。`activate_project` が状態+指示を返すエントリツール。**`check_onboarding_performed` ツールは削除**し project activation message に統合 (v1.3.0 後) — 「状態確認だけのツール」は呼ばれない/往復が無駄なので、エントリツールの戻り値に畳み込む方向に進化した。
- **Notion hosted MCP**: 18 ツールに統合、`notion-search`/`notion-fetch` を中核にトークン効率優先設計 (公式ブログ)。
- **Linear MCP**: 公開 docs にエントリツール指定・prompts・rules スニペット推奨なし (2026-07 時点)。

### 戻り値ステアリングの知見 (Anthropic 公式)
- 有効: truncation 時や error response に「次にどうすべきか」の actionable な指示を埋める (「Prompt-engineer your error responses」)。pagination/filtering/concise デフォルトで context 肥大抑制。`response_format: concise|detailed` パターン。
- ツール数は少なく consolidation 推奨、prefix による namespacing 推奨。
- リスク: 戻り値内指示は prompt injection と同型で、ホスト/セキュリティ層が警戒する領域 (OWASP MCP Tool Poisoning)。恒常的な規範 (毎回守るべきルール) は instructions/description 側、**戻り値には「今この状態での次の一手」だけ**を置くのが筋。

### 利用側リポへのスニペット配布の実例
- Context7 (upstash/context7): README「Add a Rule」節で rules/CLAUDE.md に定型文 (「Always use Context7 when I need library/API documentation...」) を追記させる運用。実在する配布例。
- Claude Code 側の自動化: SessionStart hook は stdout / `additionalContext` がそのまま Claude のコンテキストに注入される。ベンダーがフックを配る文化はまだ薄い (Codex に同等フックなし)。

## Why

ツール定義遅延ロード (tool search) が両ホストのデフォルトになったことで、「description に when-to-use を書けば見てもらえる」前提すら崩れつつある。常時ロードが保証されるのは server instructions だけ。

## How to apply

- ワークフローの入口知識 (どのツールから始めるか) は server instructions に 2KB 以内で書く。ツール戻り値には状態依存の next-step だけ。
- prompts は Claude Code 専用補助と割り切る (Codex 非対応継続)。
- エントリツールは「状態を返すだけ」にせず、Serena 式に「状態 + その状態での指示」を 1 呼び出しで返す。
