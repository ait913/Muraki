---
title: Tiptap 3 コードブロックの lowlight 色付けと Mermaid プレビュー、往復の罠 (2026-10)
category: library
project: global
tags: [tiptap, code-block, lowlight, highlight.js, mermaid, nextjs, markdown]
created: 2026-10-05
sources:
  - https://github.com/timomeh/tiptap-extension-code-block-shiki
  - https://www.notion.com/releases/2021-12-23
---

## Context
Tiptap 3.31.4 + `@tiptap/markdown` のエディタでコードブロックを Notion 相当 (言語色付け・Mermaid プレビュー) にする検討 (wasawasa)。実機検証済み。詳細は `projects/wasawasa/.knowledge/research-code-block-mermaid.md`。

## What
- `@tiptap/extension-code-block-lowlight` (MIT) は lowlight + highlight.js の Decoration で着色。common 37 言語 52 KB gz、all 192 言語 302 KB gz。ライトテーマは `highlight.js/styles/github.css` を import するだけ。言語未指定・未知言語は `highlightAuto` に落ちて誤着色するので、`highlightAuto` を空結果にした wrapper を `lowlight` に渡す
- ★ `CodeBlockLowlight.extend({...})` すると lowlight プラグインが 2 本載る (3.31.4)。`addProseMirrorPlugins() { return this.parent?.() ?? [] }` を足すと 1 本
- ★ stock の `renderMarkdown` は常に ``` 3 本で囲むため、中身に ``` を含むコードブロックが壊れる (データ破壊)。中身の最長バッククォート連 + 1 で囲む上書きが必要
- info string は `language` 属性にそのまま入って往復する (別名の正規化なし、`ts title="x"` も保持)。`ts` / `mermaid` / 言語なし / 未知言語は 3 回の往復で不動点
- Mermaid は現行 12.1.0 (MIT、DOMPurify 同梱)。`import()` を effect 内でだけ呼べば Next の build は通り SSR に乗らない。`securityLevel: 'strict'` + `suppressErrorRendering: true`、`render` は直列化、構文エラーは reject の message を文字で出す。実測 +652 KB gz を可視になった時だけ取得 (IntersectionObserver)
- Tiptap の `CodeBlock` は `enableTabIndentation` が既定 false。Shift+Enter / Mod+Enter はコードブロックを抜ける
- ★ キー操作は拡張配列の後ろが優先。`StarterKit.configure({ codeBlock: false })` で外した codeBlock を StarterKit の直後に置くと、チェックリスト項目の中のコードで Tab が TaskItem に取られてリストが字下げされる。配列の**最後**に置くと箇条書き・番号付き・チェックリストの全てでコードに空白が入る (jsdom で `view.someProp("handleKeyDown")` に keydown を渡して実測)。正規形は位置で変わらない
- mermaid の `securityLevel` の既定は `strict`。`'loose'` にすると `click A href "javascript:…"` が `<a href="javascript:…">` として SVG に残る (12.1.0、Chromium で実測)。`<img onerror>` のラベルは loose でも発火しなかった
- `lowlight` 3.3.0 は `highlight.js ~11.11.0` に依存。`code-block-lowlight` の peer `highlight.js` を 11.12 にすると 2 個入る。11.11.x に揃える。lowlight の `highlight('ts', …).data.language` は別名のまま (`ts`) で正式名に解決しない
- highlight.js の github 配色は背景 #f3f4f2 だと keyword #d73a49 (4.15)・built_in #e36209 (3.16)・comment #6a737d (4.36)・name #22863a (4.19) が WCAG 4.5:1 未満。白背景でも built_in は 3.49

## Why
着色・プレビューは表示専用なので md の正典には影響しない。

## How to apply
`StarterKit.configure({ codeBlock: false })` に上記の拡張を足し、サーバー側の正規化用拡張セットにも同じ `renderMarkdown` を入れる。
