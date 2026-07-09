---
title: best-effort DB write の `_ =` が SQL 型エラーを無音で握りつぶす
category: gotcha
tags: [go, postgres, pgx, error-handling, observability]
created: 2026-07-05
project: dandan-app
sources: [".designs/20260705-stateful-multitenant.md §5.1/§5.4", "sessions 2026-07-05 Slice1 review"]
---

## Context
dandan-app Slice 1 の last_used_at / last_seen_at (60s throttle 更新)。「失敗してもリクエストは通す」性質の write を `_ = store.TouchMCPToken(...)` で呼んでいた。

## What
Touch 系 SQL が `WHERE last_used_at < now() - $1` の `$1` (Go の time.Duration/interval 渡し) で型推論エラー (SQLSTATE 42883, `timestamptz < interval` 演算子なし) となり **100% 失敗**していたが、`_ =` で握りつぶされ、テストで「write が一切起きない」として発覚した。修正は `::timestamptz` キャスト 1 行 (tokens.go:221 / sessions.go:71)。

## Why
- best-effort write は「たまの失敗を許容する」意図だが、**恒常的な失敗 (SQL が常に不正) も同じコードパスで無音になる**。
- Postgres は placeholder の型をコンテキストで推論できないと 42883/42P18 を出す。Go 側から interval 相当を渡す式は明示キャストが要る。
- ブラックボックステストでは「配線されていない」と「配線済みだがエラー無音」が区別できない (Slice 1 レビューで前者と誤帰属しかけた)。

## How to apply
- best-effort write でも error は最低限 log に出す (`if err != nil { slog.Warn(...) }`)。`_ =` 完全無視は禁止。
- Postgres に時間演算の placeholder を渡すときは `$1::timestamptz` / `$1::interval` を明示。
- Reviewer: 「write されない」系の失敗帰属は観測レベル (「更新が起きない」) で書き、機構 (未配線 vs エラー無音) の断定はしない。
