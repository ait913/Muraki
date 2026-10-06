---
title: Markdown 正典のページに「第二の正典」(構造化データ) を埋める — 本文は id だけのブロック、参照は本文から導出、削除は参照 0 を条件に人が行う
category: pattern
tags: [markdown, tiptap, marked, notion, database, second-canon, reference-counting, soft-delete, optimistic-concurrency, mcp]
created: 2026-10-07
project: global
sources:
  - projects/wasawasa/.designs/20261007-databases.md
  - projects/wasawasa/.knowledge/research-notion-blocks-tables-db.md (D 節)
  - knowledge/pattern/markdown-canon-editor-roundtrip-normalization.md
---

## Context
wasawasa (Markdown を正典にした Notion 風ページ、Tiptap 3 + `@tiptap/markdown`) に Notion のデータベース (型付きプロパティ・タグ・ビューごとのフィルタ・別ページからのリンクドビュー) を足す設計。GFM 表は型・選択肢・ビュー・複数ページからの参照を表せないので、データは Postgres に置き、ページ本文との接続を設計する必要があった。

## What
1. **本文には中身の無い id ブロックだけを置く**: `:::database {id="…" view="…"}` + `:::` の 2 行を atom ノードとして往復する。データを本文に持たないので、AI が本文を全文置換しても、正規化が何回回ってもデータは壊れない。
2. **読み取りは Tiptap の `markdownTokenizer` でなく marked の拡張として登録し、`this.lexer.state.top` の時だけ取る**。リストの項目の中で取ると `listItem > atom` のスキーマ違反になる (負のコントロールで `check()` が例外になるのを確認)。引用・callout の中では top が真なので置ける。callout の tokenizer (`createBlockMarkdownSpec`) は `:::名前` で深さを +1、`:::` で -1 するので、2 行のブロックは callout を早く閉じない。既存コーパス 669 本の正規形は 1 本も変わらなかった。
3. **「どのページが参照しているか」は本文から導出した列で持つ**: 正規化の最後のパスの JSON から id を集め、本文を書く同じ UPDATE で `pages.database_ids uuid[]` (GIN) に入れる。別表 (refs) にすると、本文の保存・ページの完全削除・DB の完全削除の 3 経路で足し引きの同期が要る。
4. **ゴミ箱は状態でなく導出**: 「生きているページの参照が 0」をその場で数えて「参照されていない」とする。`deleted_at` の旗を立てる方式は、Cmd+Z・ページの復元・コピーしたブロック・AI の全文置換のどれかで同期し損ねる。完全な削除だけを明示の操作 (人だけ、タイトル入力、ロック後に参照 0 を再確認、参照があれば 409) にする。
5. **エディタは自分でブロックを挿入し、サーバー側の本文追記 (append) は AI / API の既定にだけ使う**: サーバーが本文を書くと開いているエディタの revision が古くなり、次の自動保存が偽の 409 になる。
6. **エクスポートの展開は `renderMarkdown` の差し替え**: 正規形を parse して、atom の `renderMarkdown` だけ「ブロック + GFM 表」を返す拡張に差し替えて serialize すると、コードブロック・リストの中の同じ文字列は展開されず、引用の中の表には `> ` が付く。既定はブロックのまま (取り込み直して往復できる)。
7. **行単位の `updated_at` 照合をするなら、ミリ秒に切り、書くたびに `greatest(now_ms, 旧 + 1ms)` にする**: JS の `Date` と ISO 文字列の往復でずれず、同じミリ秒の 2 更新も区別できる (整数 revision を使わずに `updated_at` 照合の弱点を消す)。

## Why
正典が 2 つあるとき、片方 (本文) がもう片方 (表) を「指すだけ」にすれば、往復・全文置換・正規化の不動点の議論は本文側で閉じる。参照の有無という派生値は真実 (本文) から毎回作れる形にしておけば、同期のバグの置き場所が無くなる。

## How to apply
- 文書に構造化データ (表・カンバン・埋め込み) を足すとき、データを文書に入れず id ブロックにし、marked の top 判定つき拡張で往復させ、既存コーパスで正規形が変わらないことを実走する
- 参照カウントで寿命を決めるものは、参照の真実から導出した列 + 明示の完全削除 (参照 0 の再確認つき) にし、ソフト削除の旗を持たない
- 文書を開いている編集者がいる経路では、サーバーが文書を書き換える操作を既定にしない
