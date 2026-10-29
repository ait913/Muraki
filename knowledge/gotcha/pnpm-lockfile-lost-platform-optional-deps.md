---
title: pnpm-lock.yaml からプラットフォーム別 optional 依存 (@rollup/rollup-*) が消えて Docker build だけ落ちる — `pnpm install` は「最新」と言い張るので `--fix-lockfile` で直す
category: gotcha
project: atender
tags: [pnpm, lockfile, rollup, vite, docker, coolify, codex]
created: 2026-10-30
sources:
  - sessions/2026-10-29-dbbd5b80.md
---

## Context

atender A2 (カレンダー API 削除、Codex 実装) で `pnpm-lock.yaml` が −562 行再生成された。Mac では `pnpm install --frozen-lockfile` も `vite build` も緑で、Reviewer も web build 緑と報告。main にマージして Coolify でデプロイしたら **atender-web の Docker build (linux/musl) だけ** `Error: Cannot find module @rollup/rollup-linux-x64-musl` で落ちた。API 側 (同じ lockfile) は普通に通った。

## What

- 壊れた lockfile では `rollup@4.60.3` の snapshot の `optionalDependencies` が `fsevents` だけになり、`@rollup/rollup-*` 24 パッケージ (darwin-arm64 を含む全プラットフォーム) が packages / snapshots の両方から消えていた。better-auth 系の resolution key から `(magicast)(jsdom)(msw)` の peer suffix も落ちていた
- Mac で通ったのは、`node_modules/.pnpm` に lockfile 変更前にインストール済みの `@rollup+rollup-darwin-arm64` が残っていたから。`--frozen-lockfile` は importers の spec しか照合しないので、snapshot の optional 欠落を検出しない
- `pnpm install` (9.15.0) は "Lockfile is up to date" で何もしない。**`pnpm install --fix-lockfile`** で rollup の optional 24 件と peer suffix が復元 (+281/−40、パッケージの版は不変)

## Why

pnpm は lockfile の snapshot を信頼して再解決を省く。何らかの実行 (Codex サンドボックス内の `pnpm install`、おそらくネットワーク制限下で optional のメタデータが取れなかった) が optional を落とした lockfile を書き、それが「整合している」扱いで通ってしまう。原因の特定はできていない (再現せず)。

## How to apply

- Codex/別環境が `pnpm-lock.yaml` を大きく書き換えた PR は、マージ前に **`grep -c "rollup-linux-x64-musl" pnpm-lock.yaml`** (vite を使う PJ) か、削除された packages の一覧 (`git diff` の `^-  '` 行) を見て、依存の削除に説明が付かない行が無いか確認する
- 落ちたら `pnpm install --fix-lockfile` → `--frozen-lockfile` → 該当アプリの build を Mac で通してから再デプロイ。Docker 側でキャッシュを疑う前に lockfile を疑う
- Docker build 以外で気付く手は無い (Mac の node_modules がマスクする)。本番前ゲートの "Docker build を 1 回通す" を Reviewer の仕事に入れるのが確実
