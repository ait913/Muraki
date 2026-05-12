---
title: "Next.js 15 + Prisma + better-sqlite3 + Coolify スタック概要"
category: library
project: global
tags: [next.js, prisma, sqlite, better-sqlite3, docker, coolify, deployment]
created: 2026-05-08
updated: 2026-05-12
sources:
  - https://nextjs.org/docs/app/building-your-application/upgrading/version-15
  - https://www.prisma.io/docs/v6/orm/overview/databases/sqlite
  - https://www.prisma.io/docs/orm/reference/connection-urls
  - https://github.com/WiseLibs/better-sqlite3
---

> このスタックを Coolify (Traefik、1コンテナ standalone build) にデプロイする際の **完全な Dockerfile / 落とし穴 / 復旧手順** は [`gotcha/prisma-coolify-dockerfile.md`](../gotcha/prisma-coolify-dockerfile.md) を起点に読む。本書はスタック特性の概要のみ。

## Context

Next.js 15 + Prisma 6.x + better-sqlite3 + SQLite を 1コンテナで Coolify デプロイする構成。`output: "standalone"` で薄い image を作り、SQLite は volume mount で永続化する。

## What (スタック特性)

- **Next.js 15 ブレーキングチェンジ**: `params` `searchParams` `cookies()` `headers()` `draftMode()` が **Promise (async)** 化。Turbopack が `next dev` 既定。React 19 同梱。
- **Prisma 7.x の destructive change**: `schema.prisma` の `datasource.url` が削除され `prisma.config.ts` 必須。MVP は `"prisma": "^6.19.3"` / `"@prisma/client": "^6.19.3"` で **6.x 固定**して逃げるのが速い。
- **SQLite path 規約**: `DATABASE_URL` の `file:` は schema.prisma 相対 (env 相対ではない)。prod は絶対パス `file:/app/data/prod.db` で Coolify volume と整合させる。
- **better-sqlite3 + Alpine**: native binding。builder/runner 両方に `apk add python3 make g++` (musl native compile)。
- **standalone コピー**: Next.js Node File Trace は `.node` バイナリを取りこぼす。runner は **node_modules 全コピーが安全** (selective copy で transitive 救済を狙うと `@prisma/config` の `effect` が落ちる) — 詳細は gotcha 側。
- **WAL モード**: `PRAGMA journal_mode=WAL` を better-sqlite3 公式が推奨。Next.js standalone + Docker での公式バグ報告は無し。

## Why

- standalone で native module が落ちると本番起動でクラッシュ、原因究明が面倒
- volume mount path をコード内で `./prisma/dev.db` のままにすると prod で書けない
- Prisma 7 の config 分離はアナウンスが少なく、知らずにアップグレードすると schema validation で死ぬ

## How to apply

実装手順 (Dockerfile テンプレ・entrypoint・package.json・env 例) は [`gotcha/prisma-coolify-dockerfile.md`](../gotcha/prisma-coolify-dockerfile.md) の「How to apply」を参照。デプロイ時の API 操作は [`~/.claude/skills/appily/SKILL.md`](../../../../.claude/skills/appily/SKILL.md) の「新規アプリ作成標準フロー」。

## 関連

- [`gotcha/prisma-coolify-dockerfile.md`](../gotcha/prisma-coolify-dockerfile.md) — 完全な Dockerfile + 落とし穴
- [`tool-quirk/coolify-api.md`](../tool-quirk/coolify-api.md) — Coolify API の癖
