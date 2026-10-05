---
title: Notion 風ページツリー UI の操作面の原則 (ボタンを畳む / select を捨てる)
category: pattern
tags: [notion, ui, sidebar, context-menu, move-dialog, cmdk, shadcn, page-tree]
created: 2026-10-05
project: global
sources:
  - https://www.notion.com/help/navigate-with-the-sidebar
  - https://www.notion.com/help/duplicate-delete-and-restore-content
  - https://www.notion.com/help/guides/using-slash-commands
  - https://github.com/outline/outline/tree/main/app/components/DocumentExplorer
  - https://github.com/toeverything/AFFiNE/tree/canary/packages/frontend/core/src/desktop/components/navigation-panel
---

## Context
階層ページ (ツリー + エディタ) を持つ業務ツールで「ボタンだらけ」「親ページを `<select>` で選ばせる」状態から Notion 風に直すとき。wasawasa (Next 16 + shadcn + Tailwind v4) の調査 (`projects/wasawasa/.knowledge/research-notion-pages-ui.md`) から横断化。

## What
1. **操作の入口は 3 つに絞る**: 行ホバーの `+` (子追加) と `…`、そして右クリック。`…` と右クリックは**同じアクション配列**から DropdownMenu / ContextMenu を生成する (Notion 公式ヘルプ: 「`•••` (または右クリック)」、Outline・AFFiNE も共有定義)。
2. **同じ機能への入口を増やしても UI 部品は増やさない**: Notion の `+` / `⋮⋮` / `/` は「同じ機能への近道」。アイテム定義を 1 つにして描画だけ変える。
3. **`<select>` を捨て、移動 = 検索欄 + ツリー (エクスプローラー) の Dialog**: 移動元自身と子孫は**出さない**、現在の親は出す、先頭にルート行、検索語ありはフラット + パス表示、検索語なしはツリー (→ ← で展開/折り畳み、↑↓、Enter)。Outline `DocumentExplorer` が実例 (BSL 1.1 なので読むだけ)。親選択 (新規作成) も同じ部品を再利用。
4. **削除は Undo 優先**: ゴミ箱 (サイドバー最下部、30 日保持) へ移し、ゴミ箱内ページは上部バナーで復元/完全削除、復元まで編集不可 (Notion 公式)。
5. **本文内サブページ**: `/page` で作成しページリンクブロック (アイコン + タイトル) を挿入。サイドバーの子にもなる。

## Why
操作の見える数を減らしつつ到達性は落とさない (右クリック / `…` / `/` / ショートカットで同じ操作に着く)。`<select>` は階層が見えず、大量ページで破綻する。

## How to apply
- shadcn: `context-menu` + `dropdown-menu` (radix-ui 同梱)、`command` (cmdk、`shouldFilter={false}` で自前フィルタ)、`dialog`、`collapsible`、`sonner` (Undo トースト)。
- ツリー専用ライブラリは任意: `@headless-tree/react` 1.7.0 (MIT、DnD 依存なし) / `react-arborist` 3.16.0 (MIT、react-dnd 14 依存、React 19 実機未検証)。ページ数が少ないなら再帰 Collapsible で足りる。
- 注意: Notion のメニュー項目の**順序・寸法 (インデント px、本文 ~708px 等) は公式ヘルプに無く未確認**。目視確認できる人が最終裁定する。
