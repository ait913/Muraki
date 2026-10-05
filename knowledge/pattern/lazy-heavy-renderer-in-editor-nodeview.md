---
title: エディタの NodeView に重い描画器 (Mermaid 等) を載せる — 正典はテキストのまま、可視時だけ遅延ロード + 直列キュー
category: pattern
tags: [tiptap, prosemirror, nodeview, mermaid, lazy-load, intersection-observer, bundle, xss, markdown]
created: 2026-10-05
project: global
sources:
  - projects/wasawasa/.designs/20261005-code-block-mermaid.md
  - projects/wasawasa/.knowledge/research-code-block-mermaid.md
---

## Context
wasawasa (Markdown 正典の Notion 風エディタ) でコードブロックに Mermaid のプレビューと言語の色付けを足した。mermaid は gzip 650 KB、Markdown の正典 (```` ```mermaid ```` のフェンス) は AI (MCP) とエクスポートがそのまま読む。

## What
- **正典に表示の成果物を混ぜない**: 図・色付けは NodeView / Decoration の表示専用領域に出し、md との接点はノードの属性 1 つ (info string) だけにする。表示モード (コード / プレビュー / 分割) や折り返しは md・DB に出さず NodeView の state に置く (ブロックに安定 id が無いので localStorage にも置かない)。こうすると「サーバーの正規化・MCP・エクスポートは無変更」が構造的に成り立つ
- **重い描画器は値として import する箇所を 1 つに絞る**: `lib/…/mermaid-client.ts` の `import("mermaid")` だけ。型は `import type`。そこに初期化 (`securityLevel: 'strict'`、`suppressErrorRendering: true`) と直列キュー (`render` は同時実行不可) をまとめ、読み込み失敗時は保持した Promise を捨てて再試行可能にする
- **可視時だけ描く**: プレビュー領域を `IntersectionObserver` (`rootMargin: 200px`) で見て、可視 かつ コードが変わった時に 400ms デバウンスで描く。画面外に出ても最後の結果は残す。「コード」表示の時はプレビュー要素自体を描かない (= ロードしない)
- **既定は読む形、キャレットが入ったらコードを必ず見せる**: プレビューでコードを `display: none` にすると矢印キーで見えないコードに入れてしまう。選択がノード内にある間は `reveal` (コードを上に出す) にする。判定は `useEditorState` で `editor.isFocused && from/to がノード内`
- **XSS は描画器の設定に依存していることをテストで固定する**: `dangerouslySetInnerHTML` に入れる SVG の安全性は mermaid の `strict` (DOMPurify) が担保している。負のコントロールは「設定行を消す」ではなく「`'loose'` にする」(既定が strict なので消しても緑のまま)。`click A href "javascript:…"` が loose で `<a href="javascript:…">` になる (mermaid 12.1.0 で実測)
- **遅延ロードの E2E は「チャンクの中身の印」で見分ける**: Next のチャンク名はハッシュなので、`/_next/static/**/*.js` の応答本文に描画器固有の文字列 (mermaid なら `flowchart-v2`) を含むかで判定する。アプリのコードにその文字列を書かない規約を設計に入れる
- **拡張の配列順はキー操作の優先順になる**: Tiptap は後ろの拡張が先に Tab を受ける。コードブロックの Tab インデントをリスト項目の中でも効かせるには codeBlock を拡張配列の最後に置く (前にあるとリストが字下げされる)。正規形 (出力) には効かないので、出力の比較だけでは気付かない

## Why
エディタの正典がテキストである以上、表示の豊かさは「テキスト → 表示」の片方向に閉じ込めるのが一番壊れにくい。重い依存は「初期ロードに乗らない」をコード規約 (import 1 か所) と E2E (チャンクの印) の両方で縛らないと、誰かが型以外で import した瞬間に黙って全ページに載る。

## How to apply
- リッチ表示 (図・数式・埋め込み) を足す時: md の表現を先に決め (既存記法のまま往復するか)、表示 state を md に出さない。サーバーは NodeView なしの同じ serialize で正規化する
- 重い依存: 値の import を 1 ファイルに限定 + 可視時ロード + 直列化 + 失敗時の再試行。バンドル上限を「変更前 + N KB」で E2E に入れ、基準値は実装着手時に測って doc に書く
- 安全設定に依存する描画は、既定値を確かめてから負のコントロールの壊し方を決める
- 拡張の位置を変えたら、正規形の比較 (コーパス) とキー操作 (リスト内の Tab 等) の両方を実走する
