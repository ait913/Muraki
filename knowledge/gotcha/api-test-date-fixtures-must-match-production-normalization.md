---
title: API テストの日付 fixture は本番の正規化規約 (JST midnight instant) に合わせる
category: gotcha
tags: [vitest, prisma, timezone, jst, fixture, date-normalization, bulk-api, atender]
created: 2026-06-11
project: atender
sources:
  - "atender .designs/20260611-semester-redesign.md §A bulk API / 挙動仕様 (d)(f)"
---

## Context

Atender 学期再設計の Reviewer 検証。`POST /api/attendance/bulk` 等の新 bulk API への
生成テスト 10 件が一斉に「counts が全部 0」で落ち、一見 RED (実装バグ) に見えた。

## What

**偽陽性だった**。アプリの日付正規化 (`dateStringToJstDay`) は ISO 日付文字列を
**JST midnight の instant (= 前日 15:00:00Z)** として保存する。occurrence 生成サービスも
単日 suspension POST も同じ規約 (プローブで実証: `"2026-06-03"` → `2026-06-02T15:00:00.000Z`)。

一方、テストヘルパ `createOccurrence` の既存デフォルトや生成テストの直接 DB fixture は
`new Date("2026-06-03T00:00:00.000Z")` (**UTC midnight**) を使っていた。

- **読み取り系** (`GET /api/day/:date`、overview) は JST 日レンジクエリのため
  **両方の規約を拾ってしまい**、既存テストは UTC midnight fixture でも通る → 規約ズレが潜伏。
- **等値マッチ系** (bulk の `date: { in: [...] }`) は JST instant としか一致しない →
  UTC midnight fixture だけが空振りして偽 RED。

## Why

レンジクエリは規約違いに寛容、等値クエリは厳格。寛容な読み取りパスで通ってきた
fixture 規約が、新設の等値パスで初めて破綻する。実装でなく fixture が本番と違うのが原因。

## How to apply

- fixture の日付は `new Date("YYYY-MM-DDT00:00:00+09:00")` で作る (本番規約と一致)。
- 「実装バグか fixture 違いか」は **本番経路プローブ**で切り分ける:
  実際の生成サービス (occurrenceGen) や単日 API で行を作り、その stored instant を
  `toISOString()` で観察 → 新 API に食わせる。コードを読まずに規約を実証できる。
- Architect への含意: 設計 doc に「DB に保存される date の instant 規約」を 1 行明記する
  (例: `date は JST 00:00 の instant (UTC では前日 15:00)`)。Reviewer の fixture が即座に正しくなる。
