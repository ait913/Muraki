---
title: "chrome-devtools MCP は Chrome for Testing を headless 運用、ログインは GUI スクリプト"
category: tool-quirk
project: global
tags: [chrome, chrome-devtools-mcp, headless, login, session, userDataDir]
created: 2026-05-10
sources:
  - Muraki/scripts/chrome-login.sh
---

## Context
chrome-devtools MCP で Web ページを閲覧/操作する場面。普段使い Chrome のプロファイルを汚染せず、かつ Notion など要ログインのサイトではセッションを保持したい。

## What
- MCP は **Chrome for Testing** を `--headless` で起動する。普段使い Chrome は使わない。
- ログインが必要なときだけ `Muraki/scripts/chrome-login.sh [URL ...]` で同じ `userDataDir` を共有する Chrome for Testing を **GUI 起動**してユーザーが手動ログイン。以降 headless でもセッションが引き継がれる。
- `userDataDir` のデフォルトは `~/.cache/chrome-devtools-mcp/chrome-profile`。MCP / GUI で共有する。

## Why
- 普段使い Chrome のプロファイル・セッション・拡張機能を自動化で汚染したくない。
- Chrome for Testing は自動化専用の隔離されたバイナリで、`userDataDir` を MCP とスクリプト間で共有可能。
- ヘッドレスのままだと手動ログイン (2FA・OAuth 同意画面) ができないので、GUI 起動は不可避。

## How to apply
- **MCP 登録 (user scope)**: `--headless --executablePath <Chrome for Testing path>`
  - 例: `/Users/touri/.cache/chrome-devtools-mcp/browsers/chrome/mac_arm-<version>/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing`
- **未インストール時**:
  ```
  npx -y @puppeteer/browsers install chrome@stable --path ~/.cache/chrome-devtools-mcp/browsers
  ```
- **ログイン手順**:
  1. Claude Code (MCP) を停止 — 同一 `userDataDir` を MCP と GUI で同時に握れない
  2. `Muraki/scripts/chrome-login.sh [URL]` 実行
  3. GUI で手動ログイン → Chrome 終了
  4. Claude Code 再起動 → headless でもセッション引き継ぎ
- **MCP 設定変更後は Claude Code の再起動が必須**。現セッションは旧 MCP プロセスに繋がったまま。
- **AI エージェントへの指示**: ログインが必要なサイトを操作させる前に、ユーザーに `chrome-login.sh` 実行を促す。AI 自身がパスワード等を扱う運用は避ける。
