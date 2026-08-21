---
title: "better-auth CLI 生成スキーマは TS フィールド camelCase / DB 列 snake_case"
category: gotcha
project: oni-keiri
tags: [better-auth, drizzle, postgres, schema, naming, raw-sql-fixture]
created: 2026-08-07
sources:
  - "npx @better-auth/cli@latest generate 実走 (better-auth 1.6.x, oni-keiri, 2026-08-07)"
---

## Context

oni-keiri で Reviewer が生 SQL フィクスチャ (`INSERT INTO "user" (..., "emailVerified", ...)`) を書き、24 テストが `column "emailVerified" does not exist` で全滅した。列名の正典がどちらか (camelCase / snake_case) で帰属が変わるため、CLI を実走して確定させた。

## What

better-auth 1.6.x の `@better-auth/cli generate` (drizzle/pg) の出力は:

```ts
emailVerified: boolean("email_verified").default(false).notNull()
```

つまり **TS プロパティは camelCase、DB 列名は snake_case**。session も `user_id` / `expires_at` / `ip_address` 等。

## Why

better-auth はアダプタ経由で drizzle スキーマオブジェクトのプロパティ名でアクセスするので、DB 列名は snake_case で問題なく動く。生 SQL を書くときだけ列名の実体が問題になる。

## How to apply

- テストの生 SQL フィクスチャは snake_case で書く (`email_verified`, `user_id`, `created_at`)
- 「実装 or テストのどちらが正典に合ってるか」で揉めたら、**CLI を dummy env で実走して出力を見る**のが最速の裁定 (数十秒):
  `npx -y @better-auth/cli@latest generate --config src/auth.ts --output /tmp/x.ts --yes`
- 手書き auth-schema の突合も同コマンドの出力と diff すればよい (oni-keiri は列名完全一致・index 名だけ差分だった)
