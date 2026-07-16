---
title: "docker build が package.json#prepare の lefthook/husky install で落ちる"
category: gotcha
project: global
tags: [docker, pnpm, npm, lefthook, husky, monorepo, dockerignore, git]
created: 2026-07-16
sources:
  - 実測: omatase (pnpm 11.13.0 / lefthook 2.1.10) で .git 無し context の install を実走 (2026-07-16)
  - https://pnpm.io/cli/install
---

## Context

`.dockerignore` で `.git` を除外した Docker build context で `pnpm install` (npm/yarn も同様) を
走らせると、root の `package.json#prepare` が git hook マネージャ (lefthook / husky) の
`install` を呼び、**git リポジトリが無いためビルドが落ちる**。

`.git` を除外するのは context サイズを削る定石なので、この組み合わせは踏みやすい。

## What

```json
{ "scripts": { "prepare": "lefthook install" } }
```

`.git` の無いディレクトリで `pnpm install --frozen-lockfile` を実行すると:

```
. prepare$ lefthook install
. prepare: │  > git rev-parse --path-format=absolute --show-toplevel --git-path hooks ...
. prepare: │    fatal: not a git repository (or any of the parent directories): .git
. prepare: exit status 128
. prepare: Failed
 ELIFECYCLE  Command failed with exit code 1
```

`prepare` は **install のたびに自動で走る** ライフサイクル (npm/pnpm/yarn 共通) なので回避不能。

### ★ `LEFTHOOK=0` では回避できない

`LEFTHOOK=0` は **hook の実行**を抑止する env であって、`lefthook install` 自体は走る。
実測で同じ exit 1 になった。husky の `HUSKY=0` とは効き方が違うので混同しない。

### 正解: `--ignore-scripts`

```dockerfile
RUN pnpm install --frozen-lockfile --ignore-scripts
```

**副作用を確認してから使うこと**。ネイティブ依存が postinstall でバイナリを取る作りだと壊れる。
ただし主要どころは既に prebuilt optional dep 方式に移行している:

- **sharp** (>=0.33): `@img/sharp-<platform>` という optionalDependencies の prebuilt パッケージで入る。
  **postinstall 不要**。`--ignore-scripts` でも `node_modules/@img/sharp-*` が揃うことを実測済
- pnpm の `pnpm-workspace.yaml#allowBuilds` に列挙されていても、それは
  「ビルドスクリプトを許可するか」の設定であって「必須か」ではない

## Why

`prepare` は「リポジトリを開発可能な状態にする」ためのフックで、
**開発者のローカル環境を前提にしている**。Docker build context は
「ソースのスナップショット」であって git リポジトリではないため前提が崩れる。

`.git` を context に含めれば動くが、context が肥大化するうえ
「イメージのビルドが git 履歴に依存する」という筋の悪い依存を作る。

## How to apply

1. Docker で `pnpm install` / `npm ci` する時は **`--ignore-scripts` を既定にする**
2. 外した場合に壊れる依存があるか確認する。確認は `.git` を除いた複製で実走するのが確実:
   ```sh
   rsync -a --exclude='.git' --exclude='node_modules' ./ /tmp/ctx/
   cd /tmp/ctx
   pnpm install --frozen-lockfile --ignore-scripts ; echo "exit=$?"
   ```
3. **`package.json` から `prepare` を消す方向で直さない**。
   ローカル開発者の hook 自動導入という既存の価値を Docker 都合で壊すことになる。
   `--ignore-scripts` は Docker 側だけで閉じる変更なので副作用が無い

## 関連

- [`library/nextjs16-standalone-pnpm-monorepo.md`](../library/nextjs16-standalone-pnpm-monorepo.md) — pnpm workspace の Docker 化全般
- [`tool-quirk/coolify-api.md`](../tool-quirk/coolify-api.md) — Coolify の build context は `base_directory` 依存
