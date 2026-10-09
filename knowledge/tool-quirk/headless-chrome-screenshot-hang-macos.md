---
title: headless Chrome の --screenshot は macOS で終了しない / Chrome for Testing 148 は起動後に CDP が応答しない → puppeteer-core + 普段使い Chrome
category: tool-quirk
tags: [chrome, headless, screenshot, puppeteer, chrome-for-testing, chrome-devtools-mcp, app-store]
created: 2026-10-09
project: bloom
sources:
  - projects/bloom/mocks/store/render.mjs
  - sessions/2026-10-09-acd2f2e3.md
---

## Context

App Store のプレビュー画像を HTML で組み、headless Chrome で 1290×2796 の PNG に落とそうとした (bloom `mocks/store/`)。Codex に `--headless=new --screenshot=… --window-size=…` の render.sh を書かせて実行したら 1 枚目以降が固まった。

## What

- `Google Chrome --headless=new --screenshot=out.png URL` は、この Mac (macOS 25.5、Chrome 153 / Chrome for Testing 148) では **撮影後にプロセスが終了しない** (`data:` URL でも同じ)。render.sh が 1 枚目で止まって見えたのは 2 枚目が同じ user-data-dir を掴みにいって待っていたため。
- `--virtual-time-budget` + Google Fonts のネット取得も危ない組み合わせ (仮想時間中の fetch が終わらない)。フォントは `vendor-fonts.py` でローカル woff2 に取り込む (Google Fonts の日本語は unicode-range 分割で 1 ウェイト 120 ファイル前後)。
- **Chrome for Testing 148 (`~/.cache/chrome-devtools-mcp/browsers/chrome/mac_arm-148.0.7778.97`) は puppeteer から起動しても CDP が応答せず、`launch` の 15 秒 timeout かページ操作で止まる**。同日 chrome-devtools MCP も「接続失敗」だったので同根。普段使いの `/Applications/Google Chrome.app` は puppeteer-core で 7 秒で起動・撮影・終了できた。
- `timeout` コマンドは macOS に無い (coreutils 未導入)。watchdog は `while kill -0 $pid; do sleep …` で書く。

## Why

`--screenshot` の自動終了は Chrome 側のバグ寄りの挙動で、バージョンによって直ったり戻ったりする。CfT の方は未解明 (Gatekeeper / 権限ダイアログの類ではなく、プロセスは生きていて GCM 登録エラーを吐き続ける)。

## How to apply

- 静的 HTML を画像にするなら、CLI の `--screenshot` に頼らず **puppeteer-core で launch → goto → `page.screenshot({clip})` → close** にする (`projects/bloom/mocks/store/render.mjs` が雛形。`executablePath` は Google Chrome、`CHROME=cft` で CfT を試せる)。puppeteer は一時 user-data-dir を作るのでユーザーのプロファイルは汚れない。
- 完了判定は DOM 側で `document.documentElement.dataset.ready='true'` を立てて `waitForFunction` で待つ。フォントは `document.fonts.ready` + ローカル woff2。
- chrome-devtools MCP が繋がらない日は、まず CfT を直接 `puppeteer.launch` して応答するか見る。CfT を更新するなら `~/.cache/chrome-devtools-mcp/browsers/` を入れ替える (`knowledge/tool-quirk/chrome-for-testing.md`)。
