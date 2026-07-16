---
title: Next.js 16 standalone を pnpm workspace モノレポで Docker 化する
category: library
tags: [nextjs, nextjs16, standalone, pnpm, monorepo, turborepo, docker, turbopack]
project: global
created: 2026-07-16
sources:
  - https://nextjs.org/docs/app/api-reference/config/next-config-js/output   # docs 側が version: 16.2.10 を明示
  - https://nextjs.org/docs/app/guides/upgrading/version-16
  - https://github.com/vercel/next.js/issues/84257  # open: standalone 出力にワークスペース名が入る
  - https://github.com/vercel/next.js/issues/91654  # open: Turbopack standalone × serverExternalPackages
  - 実測: omatase (next 16.2.10 / pnpm 11.13.0 / Node 25) で next build を実走 (2026-07-16)
---

## Context

pnpm workspace + Turborepo のモノレポ (`apps/web` が Next.js、`packages/*` を `workspace:*` 依存) を
`output: "standalone"` で Docker 化するとき、出力レイアウトが単一リポジトリと違う。
omatase (Next.js 16.2.10) で実際に build して確認した実測ベースの記録。

## What

### output: "standalone" は 16 でも健在、Turbopack build でも動く

- Next.js 16 から `next build` は **Turbopack が既定** (`--turbopack` 不要)。build ログに `▲ Next.js 16.2.10 (Turbopack)` と出る
- 依存ゼロに近い App Router アプリなら Turbopack + standalone は**素で通る** (実測)
- ★ 既知の未解決 issue は `serverExternalPackages` を使う場合に集中 ([#91654](https://github.com/vercel/next.js/issues/91654), [#88844](https://github.com/vercel/next.js/issues/88844))。使っていないなら踏まない

### ★ pnpm workspace では出力が `apps/<app>/` 配下にネストする

`outputFileTracingRoot` を **指定しなくても**、Next は pnpm workspace root を自動検出して
tracing root にする。結果、standalone の中身がモノレポ構造を保ったまま出る:

```
.next/standalone/
├── node_modules/                 # ← runtime 依存はここ (standalone root)
│   ├── next/ react/ react-dom/ styled-jsx/ semver/ sharp/ @img/ ...
└── apps/web/
    ├── server.js                 # ★ standalone/server.js ではない
    ├── package.json
    └── .next/                    # static は入っていない。apps/web/node_modules は無い
```

`apps/web/server.js` から Node が親方向に辿って `standalone/node_modules` を解決する。

★ **node_modules の形は `.npmrc` の `node-linker` で変わる**:

- `node-linker=hoisted` (omatase): standalone/node_modules は **symlink 無しの実ディレクトリ**が平坦に並ぶ (実測 2026-07-16)
- 既定 (isolated): `.pnpm` 仮想ストア + symlink 構成になる

どちらでも **standalone ツリーを丸ごと同じ相対関係で COPY すれば動く**
(個別ファイルを選択 COPY すると解決関係が壊れる)。

- 起動は standalone root から `node apps/web/server.js` (`.next/standalone/server.js` は**存在しない**)
- `PORT` / `HOSTNAME` env が効く (`PORT=3999 HOSTNAME=0.0.0.0 node apps/web/server.js` で 200 を実測)
- 単一リポジトリ前提の Dockerfile 例 (`COPY .next/standalone ./` → `CMD ["node","server.js"]`) は**そのままでは動かない**
- これを「バグ」として報告しているのが [#84257](https://github.com/vercel/next.js/issues/84257) (open, 15.5.0+ で発生)。直る可能性があるので **Next upgrade 時は必ず出力パスを再確認**する
- `node_modules` は相対 symlink で `.pnpm` 実体を指す。standalone ツリーを**丸ごと**同じ相対関係で COPY すれば解決する (個別ファイルを選択 COPY すると symlink が壊れる)

### `.next/static` と `public` は今も手動コピー

公式 docs (16.2.10) の原文:

> This minimal server does not copy the `public` or `.next/static` folders by default as these should ideally be handled by a CDN instead, although these folders can be copied to the `standalone/public` and `standalone/.next/static` folders manually

モノレポではコピー先も**ネストする**:

```
.next/static  →  .next/standalone/apps/web/.next/static
public        →  .next/standalone/apps/web/public
```

### transpilePackages を使うと packages/ は standalone に出ない

`workspace:*` の内部パッケージが TS ソース公開 (`main: ./src/index.ts`) で
`transpilePackages` 対象なら、ビルド時にインライン化されて
`.next/standalone/packages/` は**生成されない** (実測)。
別途 `packages/` を COPY する必要はない。

### outputFileTracingRoot は 16 でトップレベル

`experimental.outputFileTracingRoot` ではなく素の `outputFileTracingRoot`。
pnpm workspace では自動検出が効くので**明示は必須ではない**が、
検出に頼らず固定したいなら `path.join(__dirname, "../../")`。

## Why

Next は lockfile からモノレポ root を自動検出して tracing root にする。
standalone 出力は「tracing root からの相対パス構造」をそのまま再現するので、
tracing root = リポジトリ root なら `apps/web/server.js` になる。
pnpm は symlink + `.pnpm` 仮想ストアなので、node_modules を平坦化せずそのまま持ち出す必要がある。

## How to apply

Docker build context は**リポジトリ root** を取る (root の `pnpm-lock.yaml` / `pnpm-workspace.yaml` / `packages/*` が要るため)。

```dockerfile
# builder
FROM node:22-alpine AS builder
WORKDIR /repo
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
RUN corepack enable                       # packageManager のピンを尊重
COPY . .
# ★ --ignore-scripts が要る場合がある: root package.json の prepare が
#   husky/lefthook install を呼ぶと、context に .git が無いので exit 1 になる。
#   sharp は @img/sharp-* の prebuilt optional dep で入るのでスクリプト不要。
#   詳細: gotcha/docker-build-git-hook-prepare-script.md
RUN pnpm install --frozen-lockfile --ignore-scripts
RUN pnpm --filter @omatase/web build
RUN cp -r apps/web/.next/static apps/web/.next/standalone/apps/web/.next/static
# public があるときだけ:
# RUN cp -r apps/web/public apps/web/.next/standalone/apps/web/public

# runner
FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production                   # ★ Coolify env には登録しない (tool-quirk/coolify-api.md)
ENV PORT=3000
ENV HOSTNAME=0.0.0.0                      # ★ 無いと loopback bind でコンテナ外から届かない
COPY --from=builder /repo/apps/web/.next/standalone ./
EXPOSE 3000
CMD ["node", "apps/web/server.js"]        # ★ server.js 単体ではない
```

★ **`--filter <app>...` を install に付けても依存は減らない** (`node-linker=hoisted` の場合)。
hoisted は lockfile 全体から平坦ツリーを作るため、omatase では無フィルタ・フィルタとも
`added 611` で同数だった (実測)。「絞れている」という誤解を生むので付けない。

レイヤキャッシュを効かせるなら `COPY . .` の前に **manifest だけ**先に COPY して install する
(root の `package.json` / `pnpm-lock.yaml` / `pnpm-workspace.yaml` / `.npmrc` +
**全 workspace パッケージの package.json**)。1 つでも欠けると `--frozen-lockfile` が
workspace 不一致で落ちる — 使っていないパッケージ (Expo アプリ等) の package.json も要る。

**確認手順** (Next を上げたら毎回):

```sh
pnpm --filter <web> exec next build
find .next/standalone -name server.js    # パスが変わっていないか
```

## 関連

- [`tool-quirk/coolify-api.md`](../tool-quirk/coolify-api.md) — Coolify の build context は `base_directory` 依存。NODE_ENV を env 登録しない
- [`gotcha/prisma-coolify-dockerfile.md`](../gotcha/prisma-coolify-dockerfile.md) — Next.js 15 単一リポジトリ版 (こちらは `server.js` が root)
