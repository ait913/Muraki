---
title: "golang-migrate は今の版より小さい番号の migration を後から当てない (並列 doc の番号予約の罠)"
category: gotcha
project: bloom
tags: [golang-migrate, migration, postgres, parallel-design, release-order]
created: 2026-10-11
sources:
  - "bloom server/go.mod (github.com/golang-migrate/migrate/v4 v4.19.1)、server/migrations/embed.go"
  - "bloom .designs/20261011-track-3d-and-memory-log.md §10-1"
---

## Context

bloom 0.2.2 で設計 doc を並列に書き、migration 番号を doc ごとに予約した (0018〜0020 は別 doc、0021 は思い出ログ)。予約した番号の到着順と適用順がずれうる。

## What

golang-migrate の `Up` は `schema_migrations` の今の版より**大きい**番号だけを適用する。0021 が先に dev DB に当たると、後から 0018〜0020 のファイルが来ても適用されない (エラーにもならず静かに飛ばす)。`make devseed-reset` のような seed の作り直しは版を戻さない。

## Why

版は 1 つの整数で、「適用済みの集合」を持たない設計。

## How to apply

- 番号を予約した並列 doc は、**小さい番号が全部ブランチに入るまで大きい番号を dev にもデプロイしない**、をリリース順序に書く
- 着地が遅れたら大きい番号の側を付け直す (Leader が調整)。適用後に気付いたら DB の初期化しか戻し方がない
