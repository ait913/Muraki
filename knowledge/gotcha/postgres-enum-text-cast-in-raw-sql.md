---
title: PostgreSQL enum と text の比較は明示 cast が必要 (raw SQL)
category: gotcha
tags: [postgresql, prisma, raw-sql, enum]
created: 2026-05-10
project: global
sources:
  - Tsunagu MVP backend reviewer 検証で判明
  - https://www.postgresql.org/docs/current/datatype-enum.html
---

## Context
Prisma で `enum Tier { TIER1 TIER2 TIER3 }` を定義し、設計書通りの raw SQL で半径検索 + Tier フィルタを書いた:

```sql
SELECT id FROM "User"
WHERE "currentTier" IN ('TIER1','TIER2')
  AND ST_DWithin("lastKnownGeom", ST_MakePoint($1,$2)::geography, $3)
```

実行すると以下のエラー:
```
ERROR: operator does not exist: "Tier" = text
HINT: No operator matches the given name and argument types. You might need to add explicit type casts.
```

## What
PostgreSQL は ORM 経由で作られた enum 型 (e.g. `"Tier"`) と string literal (`'TIER1'`) を **暗黙には比較できない**。明示 cast が必須。

## Why
Prisma が `CREATE TYPE "Tier" AS ENUM (...)` でユーザー定義型を作ると、PostgreSQL の型システム上 `"Tier"` と `text` は別型扱い。MySQL とは違い、PostgreSQL は厳密な strict typing。

## How to apply
raw SQL で enum を比較する箇所は **必ず明示 cast** する:

```sql
-- ✅ OK
WHERE "currentTier" IN ('TIER1'::"Tier", 'TIER2'::"Tier")

-- または ANY + array literal
WHERE "currentTier" = ANY (ARRAY['TIER1','TIER2']::"Tier"[])

-- ❌ NG (暗黙キャストされない)
WHERE "currentTier" IN ('TIER1','TIER2')
```

設計書に書いた SQL を Developer がそのまま転記すると踏みやすい。**設計書側の SQL サンプルにも cast を入れて書く**のが事故防止策。
