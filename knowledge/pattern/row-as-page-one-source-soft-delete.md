---
title: 「DB の行 = ページ」を足すときの正本・生死・衝突の分担 (FK は pages 側、生死はページに一元化、タイトルは行が正本)
category: pattern
project: wasawasa
tags: [notion, database, row-page, soft-delete, optimistic-lock, revision, updated_at, schema-design, tags]
created: 2026-10-09
sources:
  - Muraki/projects/wasawasa/.designs/20261009-row-pages-and-tags.md (§4 採否, §5-6 不変条件, §6-2〜§6-6)
  - Muraki/projects/wasawasa/.designs/20261007-databases.md (§6-8 行の updated_at, §16 行のゴミ箱の不採用)
  - Muraki/projects/wasawasa/.knowledge/research-20261009-row-pages-notion-facts.md
---

## Context

ページ (Markdown 本文、楽観ロック `revision`、ゴミ箱 `deleted_at`) と、表の行 (jsonb の `cells`、楽観ロック `updated_at`、hard delete) が別々に先にあり、後から「行を開くとページになる (Notion)」を足すとき。両方が「タイトル」「削除」「衝突検出」を持っていて、二重管理になりやすい。

## What

1. **1:1 の FK は `pages.database_row_id → database_rows(id) ON DELETE CASCADE` (ページが行を指す) に置く。** 逆向き (`rows.page_id`) だと DB ごと消したときページが孤児になり、既存行の backfill も `UPDATE → INSERT` の 2 段になる。ページ側に置けば `INSERT … SELECT` 1 文で埋まり、部分 unique (`WHERE database_row_id IS NOT NULL`) で 1:1 が DB で保証される
2. **行ページは木に入れない**: `parent_id IS NULL`・`position = 0` を CHECK で固定し、木を組む全クエリ (一覧・サイドバー・パンくず用の軽量行・兄弟列挙) に共通条件 `database_row_id IS NULL` を 1 つ足す。再帰 CTE は触らなくてよい (親も子も無いので現れない)
3. **即作成**: 行の INSERT と同じ tx で行ページを 1 文の INSERT で作る (Event は行側の集約に含め、ページの `page.created` は出さない)。遅延作成は「開く」「読む API」が書き込みになり、読取 token / 他テナントの 404 判定 / ロックが読取経路に混ざる
4. **タイトルは行の title セルが正本、`pages.title` は同じ tx の控え。上限は 1 つに統一する** (切り詰めると同じ物のタイトルが 2 つになる)。ページ側からの title 書き込みは「行のセルへの書き込み」に翻訳する
5. **生死はページに一元化**: 行の削除 = 行ページを `deleted_at` (soft)。行側に `deleted_at` を持たない (旗の二重化は同期し損ねる)。行の読み取りは `LEFT JOIN pages ON pages.database_row_id = rows.id … WHERE pages.deleted_at IS NULL`。復元で id も本文も戻る。hard delete は「ページのゴミ箱からの完全な削除 (人だけ)」と「DB ごと」だけ
6. **衝突検出は資源ごと**: `cells` (タイトルを含む) は行の `updated_at`、本文はページの `revision`。**セル側の書き込みでページの `revision` を進めない** (開いているエディタの次の自動保存が偽の 409 になる)。ページ側からのタイトル書き込みはエディタが行の `updated_at` を持たないので後勝ちにし、最悪インターリーブ (表でセル → 画面でタイトル → 表で古い expected) を書き下して「最後に書いた値で収束、本文は交差しない」を確かめた

## Why

- 「同じ物の属性が 2 表にある」状態では、正本・控え・生死・ロックの 4 つを**どちらに寄せるか**を先に決めないと、各経路 (画面 / API / MCP / 削除 / 復元 / purge) の実装が勝手に片方を選んで食い違う
- 楽観ロックを 2 系統持つなら「片方の書き込みがもう片方のロック値を進めない」を不変条件にしないと、片方の画面を開いたまま他方を触っただけで 409 が出る (architect ノート 17 の「誰が revision を進めるか」)
- soft delete を既存の「ページのゴミ箱」に乗せると、復元 UI・一覧・完全削除・監査が全部既存の仕組みで済み、新しい状態機械を作らない

## How to apply

- 設計 doc には (a) 正本と控えの表 (経路ごとに「どちらを書いてどちらを同期するか」)、(b) 生死の導出 SQL (JOIN の条件)、(c) 木からの除外条件を足す場所の全列挙 (grep で)、(d) 衝突の分担表 + 最悪インターリーブ 1 本、(e) 既存行の backfill SQL (冪等) を載せる
- Reviewer 向けの負のコントロールは「同期で `revision` も進める変異 → 開いているエディタの保存が 409 になる」「soft delete を hard に戻す変異 → 本文が消える」「除外条件を外す変異 → 行ページが一覧 / 兄弟に出る」の 3 つを必ず置く
- 行ページに「子を持たせない」(422) を先に決めると、木の除外が 1 条件で済む。許すと再帰 CTE まで条件が要る
- 同じ画面に「DB の `multi_select` 列 (タグ)」と「ページ共通のタグ」が並ぶなら、欄のラベルで区別する (部品は共有してよい)
