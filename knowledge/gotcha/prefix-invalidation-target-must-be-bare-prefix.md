---
title: prefix invalidation の対象は「素の prefix」であって完全修飾 queryKey ではない
category: gotcha
project: atender
tags: [tanstack-query, cache-invalidation, ios, swift, prefix-matching, port]
created: 2026-07-01
sources:
  - Muraki/projects/atender/.designs/20260701-ios-faithful-port-architecture.md §1.4.4 / S-2
  - apps/ios/AtenderTests/QueryCacheTests.swift
---

## Context

TanStack Query の prefix invalidation を自前キャッシュ (Swift `QueryKey{ parts:[String] }` +
`hasPrefix`) に移植する際、`invalidationTargets(for:)` が返す QueryKey の作り方で事故る。

Atender iOS 移植 Phase A の Reviewer テストで検出:
- `invalidationTargets(.patchAttendance)` が `["stats","current"]` を返した (期待 `["stats"]`)
- `.deleteAttendance` が `["today","current"]` を返した (期待 `["today"]`)
- `semesters` / `day` / `timetable-suspensions` 等は素の prefix で正しく返っていた → **stats/today だけ QK factory 経由で作った**のが原因

## What

invalidation の**対象 (target)** は「前方一致で潰したい prefix」であって、
特定エントリの完全修飾 queryKey ではない。

- キャッシュエントリのキー: `QK.stats(nil)` = `["stats","current"]`、`QK.today(nil)` = `["today","current"]`
  (factory は「デフォルト引数」を末尾セグメントに埋める)
- invalidate 対象: **`QueryKey(["stats"])`** / **`QueryKey(["today"])`** (素の prefix)

target を factory (`QK.stats(nil)`) で作ると `["stats","current"]` になり、
`hasPrefix` 判定で `["stats","s1"]` (特定学期の stats) にマッチしなくなる。
= TanStack の `invalidateQueries({queryKey:["stats"]})` が全 stats を潰す挙動と乖離。
"current" エントリだけは潰れるのでデモでは気付きにくいが、キー付きバリアントで invalidate 漏れ。

設計 §1.4.4 は明示的に `例 ["today"] は ["today","current"] に一致` と書いており、
target = 素の prefix が正典。

## Why

- prefix invalidation の本質は「短いキーで長いキー群をまとめて潰す」。target を長くする =
  潰せる範囲が狭まる = 移植で最も気付きにくい invalidate 漏れになる
- factory (`QK.x(nil)`) は「取得用の完全キー」を作る道具。invalidate 用に流用すると
  デフォルト末尾セグメント ("current"/"none" 等) が余計に付く

## How to apply

- `invalidationTargets(for:)` の中では invalidate prefix は **`QueryKey(["stats"])` のように直接構築**する。
  取得用 factory (`QK.stats(_:)`) を invalidate target に流用しない
- Architect: 設計の invalidation マトリクスに「target は素の prefix」を明記し、
  factory 名ではなく `["stats"]` 表記で列挙する (Atender §1.4.4 は正しく表記済)
- Reviewer: invalidation テストは **Set 比較 + prefix の完全一致**で書く。
  `["stats","current"]` と `["stats"]` は別値なので Set 比較で確実に検出できる
  (順序非依存にするため array 順比較は避ける)
