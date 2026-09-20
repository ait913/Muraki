---
title: App Store 却下後の返信・再提出 — API だけでは通らない箇所と Web の操作順
category: library
project: global
tags: [app-store-connect, app-review, resubmit, resolution-center, puppeteer, chrome-for-testing]
created: 2026-09-21
sources: [sessions/2026-09-16-d33aab8e (Bloom. 2.1 Information Needed → 再提出)]
---

## Context

Bloom. の初回審査が 2.1 Information Needed で却下 (submission は `UNRESOLVED_ISSUES`、item は `REJECTED`)。新 build を紐付けて返信 + 再提出した時の実測。

## What

1. **Resolution Center の返信と添付は API 非対応** → Web UI。submission 詳細ページ (`/apps/<id>/distribution/reviewsubmissions/details/<submission>`) の「App Reviewに返信」→ textarea (上限 4,000 字) + `input[type=file]` → 「返信」。ブラウザを閉じると**下書きとして保存**され、次回は「下書きを続ける」から送れる (添付も残る)
2. **却下された item は API で削除も再追加もできない** (`Item was already submitted` / `reviewSubmission state does not allow adding more items`)。`PATCH reviewSubmissions {submitted:true}` は `Version is not ready to be submitted yet` で 409 のまま (時間経過では解決しない)
3. 通る順序: 新 build を `PATCH appStoreVersions/{v}/relationships/build` で紐付け → **Web のバージョン画面 (`/distribution/ios/version/inflight`) の「審査内容を更新」→ ダイアログ「新しいビルドが使用可能」で「提出」** → item が `READY_FOR_REVIEW` に戻る → ここで初めて API の `submitted:true` が 200 (`WAITING_FOR_REVIEW`)
4. ASC の Web セッションは **数日で失効** (4 日で `authResult=FAILED`)。作業直前に `scripts/chrome-login.sh` で入り直す
5. chrome-devtools MCP が落ちたときの代替: scratchpad に `npm i puppeteer-core` して、同じ `~/.cache/chrome-devtools-mcp/chrome-profile` を `userDataDir` に、Chrome for Testing を `--use-mock-keychain` で headless 起動すればセッションを共有できる。JSON ステップ駆動の小スクリプト (`ascweb.js`: goto / text / elements / click by text / eval / upload / shot) で十分。**MCP の Chrome を `pkill` すると MCP サーバーごと死ぬ**ので、MCP を使いたいなら Chrome を殺さない

## How to apply

- 却下 → 修正 build をアップロード → 紐付け (API) → 「審査内容を更新」(Web) → 返信 + 添付 (Web) → `submitted:true` (API)。返信と「審査内容を更新」の順は不問
- 録画添付は 13 MB 程度に圧縮しておくとアップロード待ちが短い (`ffmpeg -vf scale=-2:1280 -crf 23`)
