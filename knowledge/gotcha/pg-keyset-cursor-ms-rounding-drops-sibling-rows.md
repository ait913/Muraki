---
title: pg timestamptz は µs、JSON の ISO 文字列は ms — keyset cursor を ms で返すと同一 now() の兄弟行がページ境界で落ちる
category: gotcha
tags: [postgres, pagination, keyset-cursor, timestamptz, json]
created: 2026-11-03
project: wasawasa
sources:
  - sessions/2026-10-31-76c68c35.md (Reviewer DX12、設計 doc 20261103-distribution-targets §9-3)
---

## Context

wasawasa の app-uploads 一覧 (keyset pagination、`(requested_at, id) < (before, before_id)` の行値比較)。1 回の受付で複数 run を作る「束」が入り、兄弟 run が同じトランザクションの `now()` を `requested_at` に持つようになった。Reviewer のブラインドテスト (DX12) で 2 ページ目に兄弟が出ないことが発覚。

## What

- Postgres の `timestamptz` は **マイクロ秒** 精度 (`…42.899784+00`)
- node-postgres → JS `Date` → `toISOString()` は **ミリ秒** (`…42.899Z`)。cursor `next_before` をこれで返すと、DB 側の値より **小さい** 時刻になる
- 2 ページ目の `requested_at < '…42.899'` は、`.899784` の兄弟行を除外する。行値比較の第 2 要素 `id` は、第 1 要素が等しい時にしか効かないので救えない
- 1 件ずつ別トランザクションで作る run では `now()` がばらけて露呈しなかった。**同一 tx で複数行を作る設計に変わった瞬間に出る**

## Why

JSON に timestamp を載せる経路 (Date → ISO) が暗黙に精度を落とす。keyset cursor は「最後に返した行と同じ値で再開できる」ことが前提なので、精度が落ちた cursor は丸められた分だけ行を読み飛ばす。

## How to apply

- keyset cursor の時刻は **DB と同じ精度の文字列**で往復させる: SQL 側で `to_char(requested_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')` を返し、受け側はその文字列をそのまま `timestamptz` にキャストして比較する (JS `Date` を経由しない)
- もしくは cursor を `(epoch_us, id)` の opaque 文字列にする
- Reviewer の観点: 「同一受付で複数行を作る」仕様があれば、**ページ境界に兄弟行を跨がせる**テストを 1 本入れる (ページサイズ 1 で 2 兄弟)
- 関連: [[gotcha/pg-timestamptz-json-marshal-leaks-local-offset]] (同じ「JSON 経由で timestamptz が変質する」族)
