---
title: Tiptap 3 のブロック選択 (NodeRange)・右クリック・表・ドラッグハンドル位置の実測 (2026-10)
category: library
project: global
tags: [tiptap, node-range, block-selection, context-menu, radix, table, drag-handle, markdown, clipboard]
created: 2026-10-07
sources:
  - https://www.notion.com/help/keyboard-shortcuts
  - https://www.notion.com/help/columns-headings-and-dividers
  - https://tiptap.dev/docs/resources/changelog/extension-node-range
---

## Context
Markdown 正典の Tiptap 3.31.4 エディタを Notion のブロック仕様に寄せる設計前調査 (wasawasa)。素の Tiptap を esbuild で束ねた headless Chromium で実測。詳細は `projects/wasawasa/.knowledge/research-notion-blocks-tables-db.md`。

## What
- `@tiptap/extension-node-range` 3.31.4 は MIT・3.x 対応。`NodeRangeSelection` (multi-range) でブロックを複数選べる。コピーすると `text/html` に構造 (`data-pm-slice`)、`text/plain` に `clipboardTextSerializer` の返す Markdown が載り、貼付けで構造が戻る (独自 MIME 不要)。プレーンテキストの Markdown を貼っても `@tiptap/markdown` は構造化しない。
- ★ NodeRange の既定キーは Notion と違う: `Mod-a` は段階なしで全ブロック、`Shift-↑↓` は文中でも即ブロック化、`Esc` は何もしない。`key: null` で通常ドラッグでも段落をまたぐとブロック選択。段階化 (1 回目 = textblock 内、2 回目 = 全ブロック) は `priority: 1000` の `Mod-a` を 12 行足せば動く。
- ★ Radix `ContextMenuTrigger` は `composeEventHandlers` で `onContextMenu` を包むため、先に `preventDefault()` されるとメニューが開かない。ProseMirror の `handleDOMEvents.contextmenu` は React より先に走るので、そこで `preventDefault` せず、`posAtCoords` でブロック位置を記録するだけにする。右クリックでは選択が動かない。
- `@tiptap/extension-table`: `resizable: true` で列幅ドラッグ可 (`colwidth` 属性)、行列追加・削除・見出し・結合のコマンドは全て揃うが UI は無い。Markdown は `colwidth` と見出し列を捨て、見出し行オフの表に空の見出し行を足し、colspan の行はデータがずれる。セル内改行は `<br>` で往復、セル内の複数段落は `<br>` に潰れる。
- ドラッグハンドルは既定 `placement: 'left-start'` でブロック上端に揃うため、行高 26px・アイコン 16px だと中心が 4px 上、見出しだと 16px 上にずれる。`getReferencedVirtualElement` で 1 行目の矩形を返し `placement: 'left'` にすると全ブロックで 0。

## Why
Tiptap の拡張は PM の最小機能で、Notion 流の挙動 (段階選択・メニュー) はキー・イベントの上書きが要る。Markdown (GFM) は表の見た目属性を持たない。

## How to apply
Notion 風ブロック UI を作るときは NodeRange を入れてキー 3 つ (Mod-a / Shift-↑↓ / Esc) を自前で上書き。右クリックは PM で preventDefault しない。表の列幅・見出し列を保存するなら Markdown 側の記法 (区切り行のハイフン数 / コンテナ) を先に決める。
