---
title: Vitest server テストで app の DB に対し setup で migration を流さないと "no such table" で全 fail する
category: gotcha
project: global
tags: [vitest, drizzle, sqlite, hono, better-auth, test-infra, setupFiles]
created: 2026-05-26
sources:
  - omatase-demo-mvp Reviewer run (2026-05-26)
  - 設計 §9.2, §10.5 (omatase-demo-mvp)
---

## Context

Hono + Drizzle + better-sqlite3 + better-auth スタックで、設計 doc に「起動時 migration を `src/server/index.ts` で実行する」と書くと、**テストでは `index.ts` を経由しない** ため migration が走らず、全テストが `SqliteError: no such table: user` で fail する。

設計 doc §9.2 が「各テスト前に in-memory SQLite を作って drizzle migration を流す」と書いても、`makeTestDb()` helper は **別の DB インスタンス** を作るだけで、実 app の `src/server/db/client.ts` が握る DB は migration されない。app は env `DATABASE_URL=":memory:"` を見て自前で DB を open するので、その DB に対して migration を流す必要がある。

## What

テスト基盤の正しい構成:

```ts
// src/tests/setup.server.ts
process.env.DATABASE_URL ??= ":memory:";
process.env.BETTER_AUTH_URL ??= "http://localhost:5173";
process.env.BETTER_AUTH_SECRET ??= "test-secret-test-secret-test-secret";

// app の db client を import (これによって client.ts が :memory: DB を 1 回 open する)
// その直後に migration を流す
import { migrate } from "drizzle-orm/better-sqlite3/migrator";
import { db as appDb } from "@/server/db/client";

migrate(appDb as any, { migrationsFolder: "./drizzle" });
```

ポイント:

1. **setupFiles 内で import {db}** を呼ぶ → client.ts が module 初期化される → DB が 1 個 open される
2. **その直後に migrate** を呼ぶ → app が後で `app.request()` で使う DB にテーブルが揃う
3. テスト間の汚染は **truncate ヘルパ** (`PRAGMA foreign_keys = OFF; DELETE FROM ...;`) を `beforeEach` で

Vitest は **テストファイル単位で別 worker process** を生成するので、`:memory:` DB は file-scoped に独立する (worker 跨ぎでは共有されない)。1 process 内では setup の migration 1 回で十分。

## Why

- `client.ts` が module top で `new Database(":memory:")` する設計だと、import の瞬間に DB が open される。`setupFiles` でその後 migrate するタイミングが取れる
- 設計 doc §9.2 だけ読むと「test 用 helper の `makeTestDb` を呼べばよい」と誤解しがちだが、helper は **別の DB インスタンス** を返すだけで実 app には影響しない
- better-auth は `sign-in/anonymous` で **user テーブルへの INSERT** を内部で行う。テーブルが無いと `# SERVER_ERROR: SqliteError: no such table: user` で 200 を返しつつ Set-Cookie だけ吐かれる (cookie 偽セッションのまま session 取得すると user が null)
- Foreign Key 制約失敗の連鎖: cookie だけは発行されるので `loginAsGuest` は成功し、`user` 行は無い → `event.hostUserId` への FK insert で `SQLITE_CONSTRAINT_FOREIGNKEY` が発生して 500 → テストが「実装バグ」と誤判定する

## How to apply

### Architect

設計 doc 「テスト基盤」セクションに次を明記:

```md
- `setupFiles` (`src/tests/setup.server.ts`) で:
  1. `DATABASE_URL=":memory:"` を確定
  2. `src/server/db/client.ts` から `db` を import (これで :memory: が open される)
  3. `migrate(db, { migrationsFolder: "./drizzle" })` でテーブル作成
- 各テストの DB クリーニングは `src/tests/helpers/reset-db.ts` の `resetDb()` を `beforeEach` で呼ぶ
- helper の `makeTestDb()` は **別 DB を作るだけ** で実 app には影響しないことを明記
```

### Reviewer

- 最初の test run で全 fail + "no such table" を見たら、まず `setup.server.ts` を疑う
- `reset-db.ts` に truncate を実装するときは、SQLite では `DELETE FROM` で十分 (`TRUNCATE` は SQLite に無い)
- FK 制約のため逆順 (子テーブル先) で削除 or `PRAGMA foreign_keys = OFF` を一時的に外す

### Developer

- `src/server/db/client.ts` を `process.env.DATABASE_URL` を読む factory にしておく。env を setup から書き換え可能にする
- `src/server/index.ts` の起動時 migration は本番だけで必要 (テストは setup で流れる)
- migration が idempotent (CREATE TABLE IF NOT EXISTS 相当) であれば、test setup 二重実行も安全

## 関連

- [[gotcha/design-must-specify-app-export-path-for-tests]]
- [[gotcha/better-auth-test-cookie-must-match-hono-signed-format]]
- [[gotcha/hono-app-request-header-latin1-constraint]]
