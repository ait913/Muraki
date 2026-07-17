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

### ★ 現状の登録 (2026-07-17 に user スコープで再登録)

**chrome-devtools MCP は user スコープに登録済** (`~/.claude.json` の top-level `mcpServers`)。どの project からでも効く。

```
claude mcp add --scope user chrome-devtools -- \
  /Users/touri/Documents/Creatives/Developments/Muraki/scripts/chrome-devtools-mcp.sh default
```

- ラッパーが `default` プロファイル = `~/.cache/chrome-devtools-mcp/chrome-profile` を握る。
- **一度この設定が消えた事故がある** (2026-07-17): `settings.json` に許可 (`mcp__chrome-devtools__*`) とラッパーは残っていたのに、サーバー登録だけがどの config にも無い状態になっていた。おそらく過去の project-scope `.mcp.json` 運用時のファイルが worktree 整理か iCloud 移動で失われたもの。**user スコープに置いたので project ごとの `.mcp.json` に依存しなくなった**。`claude mcp list` に `chrome-devtools` が出ない時はまずここを疑う。
- **登録しても現セッションでは即使えない**。`mcp__chrome-devtools__*` ツールは Claude Code の再起動後に現れる。急ぎで現セッションのままスクショが要るなら、下の CDP 直叩き (`--screenshot` でなく `--remote-debugging-port`) で代替できる。

### project-scope で profile を分けたい場合 (並列用途)
Chrome を使う project に `.mcp.json` を置き、ラッパーの引数を `<slug>` にすれば `~/.cache/chrome-devtools-mcp/profiles/<slug>` に分離できる。user スコープと同名 (`chrome-devtools`) なら project-scope が優先される。

```jsonc
// Muraki/projects/<slug>/.mcp.json (profile を分けたい時だけ)
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
- `.mcp.json` 追加後、project root で起動した Claude Code 全てが project-scope を採用する。再起動必須。**この `.mcp.json` を作った後は git 管理に入れておくと消失事故を防げる** (2026-07-17 の消失はこれが無かったため)。

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

### ★ MCP が繋がっていないセッションでスクショが要るとき — CDP を使う。`--screenshot` CLI フラグは使うな (2026-07-17)

chrome-devtools MCP が当該セッションに接続されていない場合 (別の MCP セット / headless cron 等) にバイナリを直叩きしたくなるが、**`--headless --screenshot=out.png <url>` / `--dump-dom` のワンショット CLI フラグは Chrome 148 でハングする** (`about:blank` すら固まる。プロセスは生きているが終了しない。`sample` すると main thread が `mach_msg` で待機)。ログも空のまま。**これを「Chrome が壊れた / タブの開きすぎ / ネットワーク不通」と誤診しやすい** — 実際は全部シロで、フラグの選択ミス。

**正しい経路は CDP** (chrome-devtools MCP が内部で使っているのと同じ):

```sh
CHROME="$(ls -d ~/.cache/chrome-devtools-mcp/browsers/chrome/mac_arm-*/chrome-mac-arm64/"Google Chrome for Testing.app"/Contents/MacOS/"Google Chrome for Testing" | sort -V | tail -1)"
"$CHROME" --headless=new --disable-gpu --no-sandbox \
  --user-data-dir="$HOME/.cache/chrome-devtools-mcp/chrome-profile" \
  --remote-debugging-port=9333 about:blank &
curl -s http://127.0.0.1:9333/json/version   # 1 秒で応答する = 生きている
```

あとは CDP over WebSocket で `Page.navigate` → `Page.loadEventFired` 待ち → `Page.captureScreenshot`。`websockets` (Python 16.0) が入っている。実装例: このセッションの scratchpad `cdp_shot.py` (`Emulation.setDeviceMetricsOverride` でモバイル寸法を出せる)。

**切り分けの鉄則**: headless が「壊れた」ように見えたら、まず `about:blank` を CDP (`--remote-debugging-port` + `/json/version`) で叩く。応答すれば Chrome は無罪で、ワンショット CLI フラグ側の問題。`--screenshot` の 2 分ハングを見て環境を疑う前に経路を疑う。
