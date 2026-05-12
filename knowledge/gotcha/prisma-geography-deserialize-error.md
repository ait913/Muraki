---
title: Prisma $queryRaw が PostGIS geography カラムをデシリアライズできない
category: gotcha
tags: [prisma, postgis, postgres, geography, raw-sql, test-helper]
created: 2026-05-10
project: global
sources:
  - Muraki/projects/tsunagu/.designs/20260510-mvp-foundation.md
  - Muraki/worktrees/tsunagu-backend (Reviewer 三回目判定)
---

## Context

Prisma schema で `geom geography` を `Unsupported("geography")` で宣言している場合、
`$queryRawUnsafe` で `SELECT "geom" FROM ...` のように直接 geography カラムを
取得すると以下のエラーで落ちる:

```
PrismaClientKnownRequestError:
Raw query failed. Code: `N/A`. Message: `Failed to deserialize column of type 'geography'.
If you're using $queryRaw and this column is explicitly marked as `Unsupported` in your
Prisma schema, try casting this column to any supported Prisma type such as `String`.`
```

テストヘルパー (`readResponderGeoms` 等) で「end 後に geom が NULL になった」を
検証しようとして遭遇しがち。

## What

geography 型は Prisma の supported types に含まれないため、`$queryRaw` 系で
取得する場合は SQL 側でサポート型に **明示キャスト** する必要がある。

## Why

Prisma の RequestHandler が driver から返ってきた raw row のカラムごとの型情報を
見て JS 値に変換するが、geography は変換テーブルにない。

`Unsupported("geography")` カラムは `prisma.responder.findUnique` 等の
通常クエリでは「カラムごと結果から除外」されるため動くが、`$queryRaw` で
列名を直接書くと逃げ道がない。

## How to apply

`$queryRaw` で geography を取り出すときは必ず PostGIS の出力関数で文字列化する:

```sql
SELECT
  ST_AsText("currentGeom") AS "currentGeom",
  ST_AsText("notifiedGeom") AS "notifiedGeom"
FROM "Responder"
WHERE "id" = $1
```

NULL チェック目的なら `ST_AsText` でも `null` がそのまま返るので問題ない。
他の選択肢: `ST_AsGeoJSON(geom)::text` (GeoJSON が欲しいとき),
`ST_X(geom::geometry)`, `ST_Y(geom::geometry)` (経度緯度を数値で欲しいとき)。

「Test 側 helper の SQL も geography を直接 SELECT しないように見直す」を
PostGIS+Prisma プロジェクトのテンプレに入れておくと、Reviewer 三回目で
ようやく踏むパターンを未然に防げる。
