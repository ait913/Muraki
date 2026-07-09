---
title: MCP Apps UI の headless ハーネステストの落とし穴 (report-back / hostLog race / ui-message 形)
category: gotcha
project: dandan-app
tags: [mcp-apps, ui-testing, headless-chrome, bridge, postmessage, harness]
created: 2026-07-08
sources:
  - dandan-app internal/app/uihost_review_test.go (Slice 3 review)
  - ui/mcpapp/bridge.js (天野 dandan-mcp 0acdbdb)
---

## Context
MCP Apps (iframe UI) の bridge レベル挙動を CI 可能な形で検証する: 親ページがホスト役 (ui/initialize 応答 + tools/call を実 /mcp へ proxy) の自作ハーネス + headless Chrome for Testing + report-back 方式 (ページから /report へ POST、Go 側は exec.CommandContext で kill)。--dump-dom + --virtual-time-budget はページが timer/接続を保持すると永久ハングするので使わない。

## What
1. **同一 origin に全部載せる**: httptest の外側 mux に app mux / host.html / driver.html / report を同居させると CORS が消え、host.html が作る blob URL iframe は作成者の origin を継承するので driver (祖父) から `hostFrame.contentWindow.document.getElementById("app").contentDocument` で app DOM に直接触れる。
2. **hostLog はリクエスト記録であって応答完了ではない**: 「tools/call が log に載った」だけで次の操作をすると、応答適用前の UI を操作する race になる (例: workspace の planId 未設定のまま [紐付け] → preflight_github の引数から plan_id が消え偽 fail)。**応答適用後にしか変化しない DOM マーカー** (dandan なら `#setup-ready-note` の textContent 非空) を待ってから操作する。
3. **bridge sendMessage の ui/message params は `{role:"user", content:[{type:"text", text}]}`**。`params.text` ではない (3 シナリオが偽 fail した)。
4. **`--force-dark-mode` で headless でも `prefers-color-scheme: dark` が効く**。palette assert は body が transparent なことがあるので、実際に色が付く要素 (.card = background-secondary 等) の dark 値で見る。
5. **busy 中間状態を吸ってしまう wait**: click 直後に同期で setStatus("〜中…") が入る UI では「status が変わった」でなく「busy 文言でなくなった」まで待つ。

## Why
ハーネスは応答を観測できない (host.html は request を log するだけ) ため、driver の待機条件を仕様側の DOM 契約に倒すしかない。ui/message の形は MCP Apps bridge の仕様であってテスト側が想像で書くと系統的に外す。

## How to apply
dandan の実例: `internal/app/uihost_review_test.go` (fixture 複製 + 外側 mux + driver JS 埋め込み + シナリオ分割で 1 テスト関数 = 1 Chrome 起動 = 独立 DB 状態)。Chrome バイナリは `~/.cache/chrome-devtools-mcp/browsers/chrome/<ver>/.../Google Chrome for Testing` を env CHROME_FOR_TESTING_BIN で差し替え可、無ければ t.Skip。
