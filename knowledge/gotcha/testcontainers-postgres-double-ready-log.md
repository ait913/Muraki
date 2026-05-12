---
title: testcontainers + postgres で 「ready to accept connections」を 1 回だけ待つと早期接続失敗
category: gotcha
tags: [testcontainers, postgres, ci, vitest]
created: 2026-05-10
project: global
sources:
  - Tsunagu MVP backend reviewer 検証で判明
  - https://github.com/testcontainers/testcontainers-node/issues (公知の hint)
---

## Context
testcontainers で PostgreSQL を spawn し、global setup で `Wait.forLogMessage(/database system is ready to accept connections/i)` を使った後すぐ `prisma migrate deploy` を実行すると:

```
Error: P1001: Can't reach database server at `localhost:55001`
```

コンテナは `Up` 状態。port mapping も合っている。なのに接続できない。

## What
PostgreSQL の起動ログには **「ready to accept connections」が 2 回出る**:
1. `initdb` 完了後の一時起動
2. 初期化終了後の最終 boot

最初の 1 回目で wait strategy が通ると、その後 PG が一時 shutdown → 再起動する瞬間に migrate を叩いてしまい接続失敗。

## Why
`postgis/postgis:*` (元 `postgres` image) の entrypoint は initdb 前後で PG を一度落とす。1 回目は初期化スキーマ適用、2 回目が「本番」起動。

## How to apply
testcontainers の Wait は **2 回目** を待つようにする:

```ts
.withWaitStrategy(
  Wait.forLogMessage(/database system is ready to accept connections/i, 2)  // ← times: 2
)
```

または `Wait.forSuccessfulCommand("pg_isready -U postgres")` を使うのも安全。

設計書のテスト基盤章で testcontainers 使用を指示するときは、この Wait の指定を明記しておくと Developer/Reviewer の手戻りが減る。
