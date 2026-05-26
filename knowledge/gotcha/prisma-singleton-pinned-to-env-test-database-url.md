---
title: app の PrismaClient シングルトンが .env.test の DATABASE_URL を pin して、テスト毎の DB 切替が効かない
category: gotcha
tags: [prisma, vitest, sqlite, hono, testing, env, singleton]
created: 2026-05-26
project: atender
sources:
  - Muraki/projects/atender/.designs/20260526-v3-rooms-friends.md §9.1
  - Muraki/worktrees/atender-v3 Reviewer 第 1 回 (110 test 中 101 fail, root cause = "Error code 14: Unable to open the database file")
---

## Context

Atender Phase 4 (v3) の Reviewer 召集で、API テスト 110 件中 101 件が `PrismaClientInitializationError: Error querying the database: Error code 14: Unable to open the database file` で fail。Phase 4 で追加した friendship/room/users/meeting.bulk テストだけでなく、**既存 MVP テスト (health/auth/today/attendance 等) も全件落ちた**。

設計 doc §9.1 のテスト基盤指示はこうだった:

> **app export path**: `apps/api/src/index.ts` に `export const app` を明示
> **時刻注入**: `friendship.service.ts` / `room.service.ts` の `now?: Date` 引数を Service 関数に追加

ただし「app と Service が `PrismaClient` をどこで生成するか」「テスト env の DATABASE_URL とテスト helper の生成パスの整合をどう取るか」は書かれていない。

実態:
- `.env.test`: `DATABASE_URL="file:./tests/.tmp/test.db"` を設定
- helpers/db.ts の `createTestDb()`: `process.env.DATABASE_URL = "file:.../tests/.tmp/current-test.db"` で beforeEach 毎に上書き
- app side (`apps/api/src/db.ts` 想定) の PrismaClient は module top-level で `new PrismaClient()` → **import 時点で .env.test の `file:./tests/.tmp/test.db` を pin**
- そのファイルは実在しない (template.db は createTestDb が migrate して作るが test.db は誰も作らない)

結果: app が叩く Prisma は永久に「存在しないファイル」を見て 500。

MVP までは動いていた可能性 — Phase 4 の実装変更 (auth.ts / index.ts / db.ts のいずれか) で「PrismaClient を module top-level で生成 + Service 層が import 経由でそれを使う」構造になった瞬間に壊れる。

## What

Vitest + Prisma + 環境変数で DB を切り替えるテスト基盤において、**app 側の PrismaClient シングルトンが「import 時点の env」を pin** するために、setup.ts の `beforeEach` で `process.env.DATABASE_URL` を書き換えても無効化される。

具体的に壊れる構造:

```ts
// apps/api/src/db.ts  ← module top-level
import { PrismaClient } from "@prisma/client";
export const prisma = new PrismaClient();  // この時点の env を pin

// tests/setup.ts
beforeEach(async () => {
  const db = createTestDb();  // process.env.DATABASE_URL を上書き
  // ↑ もう遅い、apps/api/src/db.ts は既に import 済 = old URL を握ってる
});
```

対策: PrismaClient 生成を **factory 化** するか、**datasources option** で URL を毎回上書きする:

```ts
// apps/api/src/db.ts
export function createPrismaClient(databaseUrl?: string) {
  return new PrismaClient({
    datasources: databaseUrl ? { db: { url: databaseUrl } } : undefined,
  });
}
// app 起動側: const prisma = createPrismaClient(); (env 経由)
// test helper: const prisma = createPrismaClient(process.env.DATABASE_URL!);
```

または「app は **テスト時のみ app.set("prisma", testPrisma) 等で注入**」できる仕組みを設計時に決める。

## Why

- Node.js の ESM/CJS どちらでも `import` は **eager evaluate**。module top-level の `new PrismaClient()` は import 時に env を読む
- `.env.test` を vitest setup.ts の冒頭で読んでも、それは setup.ts の中だけ。app module を import した瞬間に古い env が読まれる
- `beforeAll` の中で `import` を書いても遅い (ESM では top-level でしか書けない)
- 設計 doc が「factory or singleton or DI」を明示しないと、Developer と Reviewer の前提が割れる。gotcha/design-must-specify-app-export-path-for-tests.md と同根の問題

## How to apply

### Architect (設計時必須)

設計 doc §9 「テスト基盤」セクションに以下を明示:

```md
### Prisma client 生成パターン

- `apps/api/src/db.ts`: `export function createPrismaClient(databaseUrl?: string)` (factory)
- module top-level でシングルトン生成しない
- app は `const prisma = createPrismaClient()` を `app.ts` の組み立て関数内で 1 回呼ぶ (環境変数経由で URL 解決)
- テストは `tests/helpers/db.ts` で `createPrismaClient(process.env.DATABASE_URL)` を beforeEach 毎に呼んで helper 経由で使う
- **テスト env の DATABASE_URL** = helper の生成パスと**同じ**ファイルを指す (`.env.test` を helper に合わせるか、helper を `.env.test` に合わせる)
```

### Developer

- `new PrismaClient()` を module top-level に書かない
- Service 層は `(prisma: PrismaClient, args)` の形で受け取る (DI)

### Reviewer

- 第 1 回 vitest 実行で **既存 MVP テストも全部落ちている** ことを発見したら、すぐ **RED 判定 + Leader に上申**。新規テストの fail を 1 件ずつ調べない (root cause が同じ可能性高い)
- root cause が「Prisma DB を開けない」系なら、設計の「PrismaClient 生成パターン」明示漏れを疑う

### Related

- [gotcha/design-must-specify-app-export-path-for-tests.md] — 同根: 「設計が実装エントリの構造を明示しない」事故
- [gotcha/design-spec-implicit-vs-explicit-error-codes.md] — 同根: 設計の曖昧で Reviewer が無駄に消耗する
