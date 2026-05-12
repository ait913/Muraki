---
title: Hono の errorMiddleware で AppError の status を読み損ねると全部 500 になる
category: gotcha
tags: [hono, error-handling, http-status]
created: 2026-05-10
project: global
sources:
  - Tsunagu MVP backend reviewer 検証で判明
---

## Context
Hono で `class AppError extends Error { status, code, ... }` を定義し、route handler で `throw new AppError(409, "EMAIL_TAKEN", ...)` のようにスロー。errorMiddleware で catch して JSON response を返す設計。

テストすると `expect(response.status).toBe(409)` が落ちる。**実際の status は全部 500**。stderr ログには `status: 409, code: 'EMAIL_TAKEN'` と正しく出ている。

## What
errorMiddleware が AppError を catch しているのに、`c.json(body, err.status)` ではなく `c.json(body)` のように status を渡し忘れる、もしくは `err.statusCode` 等 property 名を間違えると Hono デフォルトの 500 が返る。

スロー側はちゃんと正しい status を持っているので、ログだけ見ると「動いてる」と錯覚する。テストが拾って初めて気付く。

## Why
- Hono は thrown error を `app.onError` or middleware の catch で処理する。
- catch handler が `Response` を返す or `c.json(body, status)` で明示しない限り、デフォルトの 500 になる。
- スロー時の `err.status` は instance property として残るが、勝手に HTTP status にマップはされない。

## How to apply
1. error middleware では必ず `c.json({ error: { code, message, details } }, err.status ?? 500)` のように status を**第二引数で**渡す。
2. **integration test で 409/401/403/400 等の status を assert する**こと (200/500 だけでなく)。これがないと「ロジックは正しいのに status だけ間違ってる」を見逃す。
3. AppError の property 名 (`status` vs `statusCode` vs `httpStatus`) はチームで統一して設計書に明記する。Codex はゆらぎを起こす。
