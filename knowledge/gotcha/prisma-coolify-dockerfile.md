---
title: Prisma + better-sqlite3 + Next.js 15 standalone を Coolify Docker で動かす完全形
category: gotcha
tags: [prisma, sqlite, better-sqlite3, dockerfile, coolify, nextjs, standalone, alpine]
created: 2026-05-10
updated: 2026-05-12
project: global
sources:
  - https://www.prisma.io/docs/orm/reference/prisma-config-reference
  - https://nextjs.org/docs/app/building-your-application/upgrading/version-15
  - https://www.prisma.io/docs/v6/orm/overview/databases/sqlite
  - https://github.com/WiseLibs/better-sqlite3
  - https://github.com/coollabsio/coolify
---

> 不明な挙動が出たら Prisma / Next.js / better-sqlite3 の各公式 docs を一次情報として参照。
> このファイルは **MeishiLink + 後続デプロイで実踏したパターンの集約**。

## Context

Next.js 15 + Prisma + better-sqlite3 + SQLite を Coolify (Traefik、1コンテナ standalone build) にデプロイする構成。`output: "standalone"` で薄い image、SQLite ファイルは volume mount で永続化が前提。MeishiLink で全落とし穴を踏み抜いて整理。

### スタック特性 (前提知識)

- **Next.js 15**: `params` `searchParams` `cookies()` `headers()` `draftMode()` が **Promise (async) 化**。Turbopack が `next dev` 既定。React 19 同梱。
- **Prisma 7.x**: `schema.prisma` の `datasource.url` が削除され `prisma.config.ts` 必須 (詳細下記)。MVP は **6.x 固定**で逃げる。
- **better-sqlite3**: native binding。Alpine では musl 用の native compile が必須 → builder/runner どちらも `apk add python3 make g++` を入れる。
- **SQLite WAL**: `PRAGMA journal_mode=WAL` を better-sqlite3 公式が推奨。Next.js standalone + Docker で WAL が壊れる公式バグ報告は **無し** (個別 issue は #1155 等あるがケースバイ)。

## What

### Prisma 7 で `datasource.url` 廃止

```
P1012: The datasource property `url` is no longer supported in schema files.
Move connection URLs for Migrate to `prisma.config.ts`...
```

→ Prisma 7.x では `schema.prisma` の `datasource db { url = env("DATABASE_URL") }` が **削除**された。`prisma.config.ts` に分離するか、**Prisma 6.x にダウングレード**する。

MVP で楽したいなら `"prisma": "^6.19.3"` / `"@prisma/client": "^6.19.3"` で固定。

### SQLite の DATABASE_URL は schema.prisma 相対

Prisma の SQLite ファイルパスは **`schema.prisma` ファイルがあるディレクトリからの相対**。
- `schema.prisma` を `prisma/schema.prisma` に置き、env を `DATABASE_URL=file:./prisma/dev.db` にすると **`prisma/prisma/dev.db` に作られる** (二重 prisma)
- 正しくは `DATABASE_URL=file:./dev.db` (project root から見ると `prisma/dev.db`)

### Dockerfile multi-stage で Prisma CLI が runner に届かない

`entrypoint.sh` で `npx prisma migrate deploy` を呼ぶと、runner stage に prisma CLI がないと **`npx` が registry から最新 (Prisma 7.x) を pull** → schema validation で死ぬ。

### `node_modules/.bin/prisma` symlink 問題

選択コピー (`COPY node_modules/prisma ./node_modules/prisma` + `COPY node_modules/.bin/prisma ./node_modules/.bin/prisma`) すると Docker COPY が `.bin/prisma` symlink をデリファレンスして本体を `.bin/` 配下に置く → CLI 実行時に `prisma_schema_build_bg.wasm` を `__dirname`-relative で探して `ENOENT`。

### `@prisma/config` の transitive `effect` package 不在

runner stage に `@prisma`, `.prisma`, `prisma`, `better-sqlite3` だけ選択コピーしても、`@prisma/config` が transitive で `effect` (関数型ライブラリ) を require していて `MODULE_NOT_FOUND`。

### `NODE_ENV=production` × build stage の罠

Coolify で env 登録した `NODE_ENV=production` が builder stage の `RUN npm ci` まで影響して **devDependencies がスキップ**。Next.js が build 中に「TypeScript 入ってない」と判定して `@types/react` `@types/node@20.17.6` を勝手に install しようとし、既存 `@types/node@22` と peer 競合で `ERESOLVE` エラー。

### Coolify volume mount と DB ファイル配置

dev 用と prod 用で `DATABASE_URL` の取り扱いが分かれる:

- **dev**: `DATABASE_URL=file:./dev.db` (schema.prisma 相対なので `prisma/dev.db` に作られる)
- **prod**: `DATABASE_URL=file:/app/data/prod.db` (絶対パス)。Coolify の Storage 設定で `/app/data` を **volume mount** すること
- 初回コンテナ起動前に `chown -R node:node /app/data` で所有者を node ユーザーに合わせる (起動後の `prisma migrate deploy` が write できないと死ぬ)

### マイグレーション実行タイミング

- dev: ローカルで `npx prisma migrate dev`
- prod: Docker entrypoint で `prisma migrate deploy` → `node server.js` の順で実行。失敗したら起動しない (entrypoint は `set -e`)

## Why

- Prisma 7 は config を schema 外に分離する設計変更 (公式アナウンス少なめ)
- SQLite 相対パスは Prisma の仕様 (schema 相対) で、env-relative ではない
- Docker COPY デフォルト挙動が「symlink デリファレンス」なのは仕様
- standalone build (`output: "standalone"`) は server.js に依存を bundle するが、`prisma migrate` 用の prisma CLI 本体は別途必要
- Coolify env はビルド/ランタイム両方に流れる (build_arg と runtime env を分けてくれない)

## How to apply

このパターンを汎用 Dockerfile テンプレに:

```dockerfile
# ===== builder =====
FROM node:20-alpine AS builder
RUN apk add --no-cache python3 make g++
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npx prisma generate
RUN npm run build

# ===== runner =====
FROM node:20-alpine AS runner
RUN apk add --no-cache python3 make g++ tini
WORKDIR /app
ENV NODE_ENV=production           # ← runner だけで宣言。Coolify env では設定しない

COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/node_modules ./node_modules   # ← 全コピー (transitive 救済)
COPY entrypoint.sh ./entrypoint.sh

RUN chmod +x ./entrypoint.sh
RUN mkdir -p /app/data /app/storage/uploads
VOLUME ["/app/data", "/app/storage"]

EXPOSE 3000
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["./entrypoint.sh"]
```

```sh
# entrypoint.sh
#!/bin/sh
set -e
node node_modules/prisma/build/index.js migrate deploy   # ← bin script を node 直叩き
exec node server.js
```

```sh
# package.json
"prisma": "^6.19.3",
"@prisma/client": "^6.19.3",
```

```env
# .env (server-relative)
DATABASE_URL="file:./dev.db"             # local dev、schema.prisma 相対
DATABASE_URL="file:/app/data/prod.db"    # prod (Coolify volume)
```

サイズ比 (参考): 全コピーで image が +200〜500MB 増えるが、Prisma CLI が動く確実性とトレードオフ。MVP は確実性優先。

## 関連

- [`tool-quirk/coolify-api.md`](../tool-quirk/coolify-api.md) — Coolify API の癖、env 登録の罠 (`NODE_ENV` / `is_buildtime`)
- [`gotcha/coolify-https-redirect-loop.md`](./coolify-https-redirect-loop.md) — Cloudflare 配下のリダイレクトループ
- [`gotcha/coolify-traefik-stale-label-loop.md`](./coolify-traefik-stale-label-loop.md) — デプロイ後の routing ループ復旧
- [`pattern/coolify-deploy-debug-flow.md`](../pattern/coolify-deploy-debug-flow.md) — デプロイ詰まり 5層切り分け
- [`library/nextjs15-prisma-sqlite-coolify.md`](../library/nextjs15-prisma-sqlite-coolify.md) — スタック概要 (本書がより詳しい)
