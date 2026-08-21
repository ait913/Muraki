---
title: "vitest fileParallelism は projects 内では効かない (トップレベル限定)"
category: gotcha
project: oni-keiri
tags: [vitest, projects, fileParallelism, shared-db, truncate]
created: 2026-08-07
sources:
  - "oni-keiri Phase1 reviewer round (sessions/2026-08-06-22db0887)"
---

## Context

vitest v3 の `projects` 構成 (unit / api を分ける) で、api プロジェクトだけ共有 Postgres + beforeEach TRUNCATE 方式にした。ファイル並列だと他ファイルの TRUNCATE に user 行を消され、`session_user_id_user_id_fk` FK 違反や 401 が**大量かつ非決定的**に出る。

## What

`fileParallelism: false` を **project 内の test config に書いても無視される**。トップレベルの `test` に置いて初めて効く。

```ts
export default defineConfig({
  test: {
    fileParallelism: false,   // ← ここ。project 内では効かない
    projects: [ { test: { name: "api", ... } } ],
  },
});
```

## Why

fileParallelism はランナー全体のスケジューリング設定で、project スコープの上書き対象外 (vitest は黙って無視する。警告なし)。

## How to apply

- 共有 DB + TRUNCATE 方式のテストを含むなら、迷わずトップレベルに置く (unit が直列になるコストは誤差)
- 症状の見分け方: 「単一ファイル実行なら全緑、全体実行だと FK 違反 / 401 が混ざる」→ ほぼこれ
