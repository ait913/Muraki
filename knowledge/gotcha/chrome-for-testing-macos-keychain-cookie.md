---
title: Chrome for Testing の cookie が headless で復号できず「ログインしてるのに使えない」
category: gotcha
project: (cross)
tags: [chrome-devtools-mcp, chrome-for-testing, macos, keychain, cookie, headless, login, slack]
created: 2026-07-23
sources:
  - scripts/chrome-devtools-mcp.sh
  - scripts/chrome-login.sh
  - 実測: n-wasabi Slack ログイン (2026-07-23)
---

## Context

chrome-devtools MCP でログインが要るサイト (Slack 等) を読むとき、`chrome-login.sh` で
Chrome for Testing を GUI 起動 → 手動ログイン → 以降 headless がセッション継承、という運用。
ところが GUI で正常にログインを完了して cookie が保存されても、**headless 側では毎回ログアウト状態**になる。

## What

macOS では Chrome の cookie は **Keychain の鍵で暗号化** (`encrypted_value` の `v10` prefix) される。

- Chrome for Testing は Keychain 項目 **「Chromium Safe Storage」** に鍵を保存する
  (「Chrome for Testing Safe Storage」ではない ← `security find-generic-password -s "Chrome for Testing Safe Storage"` は rc=44 not found)
- **headless 起動時、この Keychain 項目へのアクセスに macOS 認証ダイアログが出る** → headless は応答できず
  → 鍵を取得できず `v10` cookie を復号できない → 認証 cookie (`d`) が「DB にあるのに使われない」

診断で確定した事実 (2026-07-23):
- `d` cookie は `Default/Cookies` (SQLite) に存在し `v10` 暗号化
- `security find-generic-password -w -s "Chromium Safe Storage"` は **8秒タイムアウト** = 認証ダイアログが出て誰も答えない
- cookie 保存自体は正常 (匿名 cookie は複数セッション跨いで永続)。壊れてるのは「保存」でなく「headless での復号」

## Why

macOS の Keychain ACL は「同一アプリ署名なら無プロンプトで許可」だが、headless で非対話起動された
Chrome プロセスはこの経路で弾かれ (or プロンプトが不可視のまま)、実 Keychain 鍵にアクセスできない。
GUI 起動 (可視) は鍵を取れるので v10 で書ける → 書けるが headless で読めない、の非対称が起きる。

## How to apply

**両方の Chrome 起動に `--use-mock-keychain` を付ける。** 実 Keychain を使わず決定的な固定鍵で
暗号化するので、(1) headless が認証ダイアログを出さない、(2) GUI ログインと headless が同じ鍵に
なりセッション継承できる。CI/自動化の定石。

- `scripts/chrome-devtools-mcp.sh`: `--chromeArg=--use-mock-keychain` を追加 (chrome-devtools-mcp が Chrome へ forward)
- `scripts/chrome-login.sh`: GUI 起動に `--use-mock-keychain` を直接追加

**注意**: 実 Keychain 鍵で暗号化済の既存 cookie は mock 鍵では読めない → **切り替え後は 1 回だけ再ログインが必要**。以降は恒久的に効く。

### 付随する運用の罠 (同時に踏んだ)

- **profile を掴むプロセスの kill は「ブラウザだけ」狙う**。ブラウザは `--user-data-dir=<path>` (イコール区切り)、
  MCP wrapper は `--userDataDir <path>` (スペース区切り)。`pkill -f "chrome-devtools-mcp/chrome-profile"` だと
  wrapper (npm exec) まで巻き込んで MCP が落ちる。ブラウザだけなら `pkill -f -- "--user-data-dir=<path>"`。
- MCP を落とした後は `/mcp` で reconnect すると wrapper が再 exec されるので、**スクリプト編集の反映もこれで効く**。
- Slack canvas は web クライアントで `/docs/` 直リンクが channel に飛ばされ開けない。channel 内の canvas
  **タイトルボタンを click** すると全画面 canvas ビューに入り、`[role=main]` の innerText で全文が取れる
  (インラインプレビューは途中で truncate される)。
