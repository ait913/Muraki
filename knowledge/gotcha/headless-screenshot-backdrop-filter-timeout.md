---
title: chrome-devtools MCP の headless スクショは backdrop-filter 多用ページで captureScreenshot がタイムアウト
category: gotcha
project: global
tags: [chrome-devtools-mcp, screenshot, backdrop-filter, glassmorphism, headless, blur]
created: 2026-06-11
sources:
  - kinketsu-taisaku moneylog 忠実 UI の実機スクショで実踏 (2026-06-11)
---

## Context

frosted glass (glassmorphism) UI を chrome-devtools MCP の headless で `take_screenshot` すると `Page.captureScreenshot timed out` で撮れない。`backdrop-filter: blur()` を**複数のカードに**当てているページで再現。

## What

- `*.card { backdrop-filter: blur(8px) }` のように **backdrop-filter を持つ要素が画面に多数**あると、GPU 無しの headless がソフトウェアラスタライズで詰まり `captureScreenshot` が protocolTimeout を超える (MCP 側 timeout は変更不可)。
- 単発の `filter: blur(40px)` (ぼかし blob 1 個など) は**問題なし**。効くのは **backdrop-filter (背景透過ぼかし) の重ね**。
- ページ自体は正常 (`scrollHeight` 通常・`getAnimations()` 空・`document.fonts.status==="loaded"`・巨大要素なし)。**UI のバグではなくスクショ環境の制約**。
- 切り分け: 別の軽いページ (backdrop-filter 無し) は同じ chrome で撮れる → chrome は健全、当該ページ固有。

## Why

backdrop-filter は「背後のピクセルを読んでぼかして合成」する高コスト処理。headless Chrome for Testing は GPU 非対応のことが多く、複数レイヤ分を CPU で処理すると 1 フレーム rasterize に数十秒かかり captureScreenshot が返らない。

## How to apply

スクショ直前に backdrop-filter だけ無効化する CSS を inject して撮る (背景が単色なら blur-through はほぼ視覚差が出ないので実質ロスなし):

```js
// evaluate_script
const s=document.createElement('style');
s.textContent='*{backdrop-filter:none !important;-webkit-backdrop-filter:none !important;}';
document.head.appendChild(s);
// → この後 take_screenshot は通る
```

- `filter: blur()` の **blob (発光) は残してよい** (単発は軽い)。発光を見せたいなら backdrop-filter だけ消す。
- 確認: inject 後 `getComputedStyle(card).backdropFilter === "none"` を assert してから撮る。
- DPR を下げる (`emulate viewport 402x874x1`) のも軽くなるが、根治は backdrop-filter 無効化。
- dark は `emulate({colorScheme:"dark"})` で prefers-color-scheme を切り替えて撮る。

## 関連
- [[tool-quirk/chrome-for-testing]] — headless 運用全般
- [[pattern/moneylog-design-language]] — frosted glass を多用する UI (本 gotcha の発生源)
