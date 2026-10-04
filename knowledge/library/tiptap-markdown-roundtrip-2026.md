---
title: Tiptap 3 / BlockNote / Milkdown の Markdown 往復と Next 16 での注意 (2026-10)
category: library
project: global
tags: [tiptap, blocknote, milkdown, markdown, prosemirror, nextjs, pg_trgm]
created: 2026-10-05
sources:
  - https://tiptap.dev/docs/editor/markdown
  - https://www.blocknotejs.org/docs/features/import/markdown
  - https://www.blocknotejs.org/pricing
---

## Context
Markdown を正典にするドキュメントエディタを Next 16 / React 19 に載せる検討 (wasawasa)。実機 spike で比較した。詳細表は `projects/wasawasa/.knowledge/research-doc-editor.md`。

## What
- **Tiptap 3 + 公式 `@tiptap/markdown` (3.31.4, MIT)** は表の列幅パディング以外ほぼ無損失で、出力を再読込しても冪等。落ちるのは生 HTML (`<details>` 等は中身テキストだけ残る) と脚注 (リテラル化)。YAML frontmatter は本文扱いで壊れるので呼び出し側で剥がす。
- **BlockNote 0.55** の `blocksToMarkdownLossy` は list マーカー `-`→`*`、hr→`***`、段落内改行→`\`+空白、list 内コードブロックが外に出る、表セル内 `<br>` で表が壊れる。Markdown 正典には向かない (内部正典は Block JSON)。`xl-*` パッケージ (multi-column / docx / pdf / AI) のみ GPL-3.0 OR 商用 ($195/月)、core/react/shadcn は MPL-2.0 で商用 OK。
- Milkdown 7.22 (remark ベース) は生 HTML・脚注も保持し最も忠実だが、headless では画像が `<br />` に化けた (`title` null の attr validation エラー、ブラウザ未確認)。
- Tiptap で Notion 風ブロックを md に逃がすには `createBlockMarkdownSpec` を **`Node.create({ ...spec })` とフラットに spread** (`markdown: spec` のネストは 3.31 では無視される)。`:::callout {type="warning"}` ... `:::` で冪等に往復。
- Next 16: Tiptap は `useEditor({ immediatelyRender: false })` で SSR OK。BlockNote は `"use client"` だけだと prerender で `window is not defined`、`next/dynamic(..., { ssr: false })` が必要。Turbopack build は First Load JS 表を出さないので、バンドルは Playwright で `/_next/static/**/*.js` を足し合わせる (Tiptap 構成 +214KB gzip、BlockNote shadcn 構成 +315KB gzip)。
- Tiptap の slash command UI は付属しない (`@tiptap/suggestion` で自作)。ドラッグハンドル `@tiptap/extension-drag-handle-react` は MIT。BlockNote は slash / side menu 付属。
- Novel は最終 push 2025-01-18 で実質停止。

## Why
Tiptap は ProseMirror doc ⇄ marked トークンの対応が素直。BlockNote は Block JSON が主で Markdown は輸出入の一形式に過ぎない (docs も "lossy" を明言)。

## How to apply
Markdown 正典なら Tiptap。保存前に frontmatter を剥がし、保存は常に `editor.getMarkdown()` の正規形に統一 (冪等)。Pro 機能 (コメント / DOCX / AI) は使わない前提で MIT 範囲に収める。`@tiptap/markdown` は early release なので pin。pg_trgm での日本語検索は DB が C locale だと trigram が 0 個になる点に注意 (別メモ: wasawasa research)。
