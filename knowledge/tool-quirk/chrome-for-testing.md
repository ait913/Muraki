---
title: "chrome-devtools MCP は Chrome for Testing を headless 運用、project 並列は userDataDir 分離"
category: tool-quirk
project: global
tags: [chrome, chrome-devtools-mcp, headless, login, session, userDataDir, parallel]
created: 2026-05-10
sources:
  - Muraki/scripts/chrome-login.sh
  - Muraki/scripts/chrome-devtools-mcp.sh
---

## Context
chrome-devtools MCP で Web ページを閲覧/操作する場面。普段使い Chrome のプロファイルを汚染せず、Notion など要ログインのサイトではセッションを保持し、かつ複数 Claude Code セッションを **同時並列** で動かしたい。

## What
- MCP は **Chrome for Testing** を `--headless` で起動する。普段使い Chrome は使わない。
- Chrome は `userDataDir` を **排他ロック**するので、同じ userDataDir を握る MCP セッションは 1 つしか同時起動できない。並列したい場合は userDataDir を分ける。
- 既定構成:
  - **user-scope MCP** (`~/.claude.json`) → `~/.cache/chrome-devtools-mcp/chrome-profile` (legacy default)
  - **project-scope MCP** (`<project>/.mcp.json`) → `~/.cache/chrome-devtools-mcp/profiles/<slug>` で project 単位に分離
- ログインが必要なときだけ `Muraki/scripts/chrome-login.sh [--profile <slug>] [URL ...]` で対応 `userDataDir` を共有する Chrome for Testing を **GUI 起動**してユーザーが手動ログイン。以降 headless でもセッションが引き継がれる。

## Why
- 普段使い Chrome のプロファイル・セッション・拡張機能を自動化で汚染したくない。
- Chrome for Testing は自動化専用の隔離されたバイナリで、`userDataDir` を MCP とスクリプト間で共有可能。
- Chrome のプロファイルロック制約により、true 並列 = userDataDir を分けるしかない。**project 単位**で分離するのが Muraki ワークフロー (worktree は同 project = 同 profile) と整合する。
- ヘッドレスのままだと手動ログイン (2FA・OAuth 同意画面) ができないので、GUI 起動は不可避。

## How to apply

### user-scope MCP (Muraki 外 / 単一セッション用途)
`~/.claude.json` の chrome-devtools 設定。`--headless --executablePath <Chrome for Testing path>` で `~/.cache/chrome-devtools-mcp/chrome-profile` を共有。Muraki 内でも project に `.mcp.json` がなければこれが効く。

### project-scope MCP (Muraki project 並列用途)
Chrome を使う Muraki project に `.mcp.json` を置き、ラッパー経由で profile を分ける。

```jsonc
// Muraki/projects/<slug>/.mcp.json
{
  "mcpServers": {
    "chrome-devtools": {
      "type": "stdio",
      "command": "/Users/touri/Documents/Creatives/Developments/Muraki/scripts/chrome-devtools-mcp.sh",
      "args": ["<slug>"]
    }
  }
}
```

- ラッパー `Muraki/scripts/chrome-devtools-mcp.sh` が `--userDataDir ~/.cache/chrome-devtools-mcp/profiles/<slug>` と最新 Chrome for Testing パスを補って `chrome-devtools-mcp@latest` を起動する。
- worktree も同 project の `.mcp.json` を共有 = 同 profile。worktree 同士の並列はロック衝突する (その時は profile を更に分けるか `--isolated` 検討)。
- `.mcp.json` 追加後、project root で起動した Claude Code 全てが project-scope を採用する。再起動必須。

### Chrome for Testing 未インストール時
```
npx -y @puppeteer/browsers install chrome@stable --path ~/.cache/chrome-devtools-mcp/browsers
```

### ログイン手順
1. 該当 profile の **headless Chrome プロセスだけ kill** — 同一 `userDataDir` を MCP と GUI で同時に握れない。Claude Code 自体は停止不要 (MCP は次ツール呼び出しで自動再起動するので現セッションは生き残る)
   ```
   pkill -f "chrome-devtools-mcp/chrome-profile"          # legacy default
   pkill -f "chrome-devtools-mcp/profiles/<slug>"         # project-scope
   ```
2. `Muraki/scripts/chrome-login.sh [--profile <slug>] [URL]` 実行
   - `--profile` 省略時: legacy default (`chrome-profile`)
   - `--profile <slug>` 指定時: `profiles/<slug>` にログイン
   - スクリプトは既に同 `userDataDir` を握るプロセスを検出して abort するので、step 1 を忘れても安全
3. GUI で手動ログイン → Chrome 終了 (プロファイルにセッション保存)
4. 次の MCP ツール呼び出しで headless が自動再起動 → ログインセッション引き継ぎ

### 注意
- **MCP 設定変更** (`.mcp.json` 編集) 後は Claude Code の **再起動が必須**。現セッションは旧 MCP プロセスに繋がったまま。ログイン手順での Chrome プロセス kill とは別物。
- Notion 等のログインは **profile ごとに 1 回ずつ必要**。project を増やすほどログイン手数が増える tradeoff。
- AI エージェントがログイン作業を代行しない (パスワード等を扱わせない)。
