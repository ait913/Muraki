---
title: Notion 風ページツリー UI の操作面の原則 (ボタンを畳む / select を捨てる / 本文中のページリンク)
category: pattern
tags: [notion, ui, sidebar, context-menu, move-dialog, cmdk, shadcn, page-tree, tiptap, markdown, marked]
created: 2026-10-05
project: global
sources:
  - https://www.notion.com/help/navigate-with-the-sidebar
  - https://www.notion.com/help/duplicate-delete-and-restore-content
  - https://www.notion.com/help/guides/using-slash-commands
  - https://github.com/outline/outline/tree/main/app/components/DocumentExplorer
  - https://github.com/toeverything/AFFiNE/tree/canary/packages/frontend/core/src/desktop/components/navigation-panel
  - projects/wasawasa/.designs/20261005-pages-markdown-docs.md (§4-7, §10。2026-10-05 (2))
---

## Context
階層ページ (ツリー + エディタ) を持つ業務ツールで「ボタンだらけ」「親ページを `<select>` で選ばせる」状態から Notion 風に直すとき。wasawasa (Next 16 + shadcn + Tailwind v4 + Tiptap 3、Markdown 正典) の調査 (`projects/wasawasa/.knowledge/research-notion-pages-ui.md`) と設計 (上の §10) から横断化。

## What
1. **操作の入口は 4 つに絞る**: ツリー行ホバーの `+` (子追加。モーダルを出さず「無題」で即作成して遷移、タイトル欄にフォーカス = Notion と同じ) と `…`、右クリック (タッチは長押し)、エディタの `/`。行・画面に他の操作ボタンを並べない (例外は「+ ページを追加」「ゴミ箱」の常設行と、空状態の 1 ボタンくらい)。
2. **メニューは 1 つの配列から DropdownMenu と ContextMenu の両方を描く** (Notion 公式「`•••` (または右クリック)」、Outline・AFFiNE も共有定義)。項目の順序は配列の並びだけで決まるようにし、E2E は**配列を import して DOM と比べる** (順序を固定するテストを書かない = 実機で見て並べ替えても赤くならない)。
3. **`<select>` を捨て、「ページを選ぶ」部品 (検索欄 + インデント付きツリー) を 1 つ作って全ての選択に使う** (移動先・新規作成の親・別エンティティへの紐付け)。移動元自身と子孫は**出さない**、深さ超過は disabled + 理由、現在の親には「現在の場所」、先頭にルート行、検索語ありはフラット + パス表示、↑↓ Enter に加えて → ← で展開/折り畳み。Outline `DocumentExplorer` が実例 (BSL 1.1 なので読むだけ)。モーダルは同時 1 枚なので、部品は別ダイアログでなく**モーダルの本文に埋め込める**形にする。
4. **DnD を入れないなら、移動ダイアログに「位置」を残す**: 移動先を選んだら「先頭 / 「X」の後 / 末尾」の小さいメニュー (既定 末尾)。即移動にすると並べ替えの手段が消える。
5. **ゴミ箱へは確認なし + toast の [元に戻す]**: 戻せる操作に確認モーダルを挟まない。完全削除だけ確認。ゴミ箱内のページは上部バナー (復元 / 完全に削除) + 読み取り専用。
6. **本文中の子ページ (`/page`) は「段落単独のリンク」を正典にして atom ブロックとして往復**し、表示は id で引いた**今のタイトル**にする (Markdown のラベルは控え。開いただけで本文を書き換えない)。リンク先が無ければ「削除済みページ」。リンクのブロックを消しても子ページは消さない (本文の全文置換をする AI や Cmd+Z と副作用がぶつかる)。
7. **ツリーからの名前の変更は、開いているページならエディタの保存経路に渡す**: 楽観ロック (revision) の API を別経路で叩くと、開いているエディタの revision が古くなって次の自動保存が偽の衝突になる。「今開いているページの窓口」(rename / flush / focusTitle) を context で持つ。

## Why
操作の見える数を減らしつつ到達性は落とさない (右クリック / `…` / `/` / ショートカットで同じ操作に着く)。`<select>` は階層が見えず、数十件で探せない。1 配列にしないと右クリックと `…` の項目が片方だけずれる。

## How to apply
- shadcn: `context-menu` + `dropdown-menu` (radix-ui 同梱)、`command` (cmdk、`shouldFilter={false}` で除外・絞り込みは自前の純関数 `pickerRows`、→ ← は `Command` の `onKeyDown`)、`collapsible`、`sonner` (Undo トースト)。ツリー専用ライブラリは DnD をやらないなら不要 (数百件なら仮想化も不要)。
- `+` `…` は `opacity` で隠す (display:none にしない = Tab で届き、ホバーで行の幅が揺れない)。タッチ環境では `…` を常時薄く出し、`+` はメニューに逃がす。iOS は行のリンクの長押しでリンクプレビューが ContextMenu を食うので `-webkit-touch-callout: none`。
- 同じツリーをサイドバーと一覧の 2 か所に出すなら data-testid に接頭辞を付ける (Playwright の `getByTestId` が 2 つに当たる)。展開状態は `useSyncExternalStore` の 1 store で共有。
- タイトルが必須の DB でも「無題」を既定値にし、ページ画面では「保存値 = 無題」を空欄 + placeholder で見せる (空で確定したら「無題」で保存)。
- **Tiptap 3.31 + `@tiptap/markdown` でブロックの Markdown 記法を足すときの落とし穴**: 拡張の `markdownTokenizer.tokenize(src, tokens, helper)` には marked の lexer が渡らないので「リストの項目の中か」を判定できない。項目の中でも取ると `listItem` の先頭が paragraph でなくなりスキーマ違反 (`check()` で `Invalid content for node listItem`)。marked の拡張として直接登録し `this.lexer.state.top` で文書の直下 (と引用の中) だけ取る。そのために `new Marked()` を作って `MarkdownManager({ marked })` と `Markdown.configure({ marked })` の**両方**に渡す (片方だけだと正規形とエディタの出力がずれる)。既定の `marked` はグローバルのシングルトンで、`MarkdownManager` を作るたびに拡張の tokenizer が積み増される点にも注意。足した後は手元の実コーパスで旧正規形との一致を確かめる (wasawasa: Muraki の md 669 本で全一致)。
- 注意: Notion のメニュー項目の**順序・寸法 (インデント px、本文 ~708px 等) は公式ヘルプに無く未確認**。目視確認できる人が最終裁定する。推測で Notion の未確認機能 (ホバーでアイコンが三角に変わる等) を入れない。
