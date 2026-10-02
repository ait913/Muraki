---
title: embedded-postgres の exit hook が vitest の exit code を 0 に握り潰す — 失敗していても `pnpm test` が成功に見える
category: gotcha
project: global
tags: [vitest, embedded-postgres, exit-code, ci, test-harness, async-exit-hook]
created: 2026-10-03
sources:
  - sessions/2026-10-01-37ab5196.md (wasawasa Phase 2 Reviewer)
  - projects/wasawasa/tests/helpers/exit-code-guard.ts
---

## Context

wasawasa のテスト基盤は Docker 不要にするため `embedded-postgres` (npm) でテスト用 Postgres をプロセス内に立てる。Phase 2 の途中で Developer が「`pnpm test` は 3 本落ちているのに exit 0 を返す」と報告し、Leader も「test exit 0 なのに Tests 1 failed」のログを 2 回見ていた。

## What

- `embedded-postgres` は import 時に `async-exit-hook` を登録する
- その `beforeExit` ハンドラが後始末の末に **`process.exit(0)` を呼ぶ**ため、vitest が設定した `process.exitCode = 1` が上書きされる
- 結果、失敗があっても `pnpm test` / `pnpm test:e2e` の exit code は 0。CI やスクリプトの `set -e` では検出できない

## Why

ライブラリの「お行儀の良い後始末」が、ホストプロセスの終了コードの所有権を奪っている。vitest 側はハンドラの存在を知らず、`exitCode` を立てて自然終了に任せるだけなので負ける。

## How to apply

- 対処: テストのグローバル setup で **`beforeExit` / `exit` のリスナーを全て外す**ヘルパー (`tests/helpers/exit-code-guard.ts`) を embedded-postgres の import 直後に読み込む。Postgres とスタブの後始末は自前の teardown で行う
- 判定規律: **exit code を信用せず、ログの `FAIL` 行 / `Tests N failed` で判定する** (Reviewer / Leader とも)。exit code で自動判定するスクリプトは、わざと 1 本落とす probe で「exit 1 になること」を確認してから信用する
- 同じ構造は `async-exit-hook` を使う他ライブラリ (一部の DB ランナー、ブラウザランチャ) でも起こり得る。「テストが全部落ちているのに緑」の報告が来たら、まず `process.listeners("beforeExit")` を疑う
