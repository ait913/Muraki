---
title: ProseMirror で Notion 風ブロック選択 — NodeRange + 自前キー、text/html に構造・text/plain に Markdown、右クリックは記録だけ
category: pattern
tags: [prosemirror, tiptap, node-range, block-selection, clipboard, markdown, context-menu, radix, drag-handle, notion]
created: 2026-10-07
project: global
sources:
  - projects/wasawasa/.designs/20261005-pages-markdown-docs.md
  - projects/wasawasa/.knowledge/research-notion-blocks-tables-db.md
  - knowledge/library/tiptap-block-selection-table-2026.md
---

## Context
wasawasa (Markdown 正典の Tiptap 3.31.4 エディタ) を Notion のブロック仕様に寄せた設計 (4)。Touri の要望は「ブロックごとの全選択・コピー」「右クリックで Notion 風メニュー」「ドラッグハンドルの縦位置」。

## What
- **選択の状態を T (テキスト) と B (ブロック = `NodeRangeSelection` depth 0) の 2 つに分け、キーごとに T / B の列を持つ表で仕様にする。** `@tiptap/extension-node-range` は B の器として使い、**既定のキーは全部外す** (`NodeRange.extend({ addKeyboardShortcuts: () => ({}) })`)。既定の Shift+↑↓ は文中でも即ブロック化してテキストの行選択を潰し、Mod+A は段階なしで全選択になる。自前の拡張 (priority 1000) が Mod+A の段階 (1 回目 = textblock の中身、2 回目 = 全ブロック)・Esc (今いるブロックを B)・Shift+↑↓ (B の時だけ伸縮)・Delete・Mod+D・Mod+Shift+↑↓ を持つ。T の時は false を返して既定に渡す
- **ブロックの単位を 1 つに決めて全入口で揃える** (キー・右クリック・ドラッグハンドル)。Markdown 正典なら「文書の直下のブロック」が素直 (リストは全体で 1 ブロック)。Notion の「リスト項目もブロック」は lift / sink とリストの分割を伴うので、やるなら別の作業として明示的に諦める
- **StarterKit 3 の `TrailingNode` が末尾までの NodeRange を伸ばす**: 最後のブロックが段落でないと次の transaction で空の段落が足され、末尾の位置で張った選択がその写像で空の段落まで伸びる。B を張る transaction では先に自分で空の段落を足す
- **クリップボードは独自 MIME 不要**: ProseMirror 既定の `text/html` (`data-pm-slice`) が構造を運び貼り付けで戻る。`clipboardTextSerializer` で `text/plain` を Markdown にする — ただし 1 つの段落の中の文字選択は既定 (文字だけ) に残す (Slack 等に `**` が入るため)
- **右クリックは「位置を記録するだけ、`preventDefault` しない」**。Radix の `ContextMenuTrigger` は `composeEventHandlers` で包むので、先に誰かが `preventDefault` するとメニューを開く処理が丸ごと飛ぶ。記録は React の `onContextMenuCapture` (+ 長押し用の touch の `onPointerDownCapture`) に 1 か所でまとめると NodeView の部品の上でも取れる。選択の寄せ (クリックしたブロックが選択に入っていなければそこを B) は `onOpenChange(true)` で行う
- **ドラッグハンドルを Radix の Trigger にしない**: Trigger は `pointerdown` で開いて `preventDefault` するのでドラッグと干渉する。ハンドルは素の `<button onClick>`、メニューは `open` を state で持ち、別の 0×0 のアンカー要素を Trigger にして位置だけ合わせる。開いている間は `lockDragHandle()`
- **ハンドルの縦位置は「1 行目の矩形」を参照にして `placement: 'left'`**: 既定の `left-start` は上端揃えで、行の高さとアイコンの大きさの差だけずれる (見出しは更にずれる)。補正値 (`offset`) では見出しと段落で値が違って揃わない。1 行目 = 基準要素の中の最初の空白でない文字ノードの `Range.getClientRects()[0]` の縦中央、文字が無ければ箱の規則。ハンドルの子は `flex` (inline だと親の行の高さが乗る)
- メニュー項目は入口 (右クリック / ハンドル / キー) をまたいで 1 配列から描き、E2E は配列を import して順を比べる (順序を Touri が直しても赤くならない)

## Why
ProseMirror の拡張は最小機能で、Notion 流の段階的な選択やメニューはキー・イベントの上書きが要る。上書きを「どの状態で何をするか」の表にしないと、ライブラリ既定と自前のキーが同じ状態で両方動く (Shift+↑↓ のように) か、どちらも動かない穴が出る。

## How to apply
- ブロック選択を足す時は、T / B のキー表を先に書き、ライブラリの既定キーを全て外してから自前で埋める。負のコントロールは「段階の分岐を消す」「既定キーを戻す」
- 右クリックメニューを Radix で出すなら、エディタ側のどのハンドラも `contextmenu` で `preventDefault` しないことを grep で確かめ、`preventDefault` を足すと赤くなる E2E を 1 本置く
- 位置合わせの E2E は「アイコンの中心 − 期待値 ≤ 0.5px」を、期待値をテスト自身が DOM から測って書く (実装の関数を import すると自己参照になる)
