---
title: Go slog の Handler wrapper で rec.AddAttrs した属性は WithGroup の中に入る
category: gotcha
tags: [go, slog, logging, request-id]
created: 2026-10-13
project: bloom
sources: [.designs/20261013-identity-email-name-and-logs.md D14 / §5-6-2, sessions/2026-10-13-800a28fa]
---

## Context
bloom S1 (アクセスログ整備) で、`request_id` を ctx から全 slog 行に付ける `requestIDHandler` (slog.Handler を包み `Handle(ctx, rec)` で `rec.AddAttrs(slog.String("request_id", id))`) を Reviewer が検証した。

## What
`slog.Default().WithGroup("g").InfoContext(ctx, "d", "x", 1)` の出力は `{"msg":"d","g":{"x":1,"request_id":"…"}}` になる。
`WithAttrs` / 素の `InfoContext` では top-level に付く。`WithGroup` 経由だけ group の中に入る。

## Why
`Handle` が受け取る `Record` の属性は「現在開いている group」に属する。wrapper が `rec.AddAttrs` で足した属性も内側 handler から見れば record の属性なので、`WithGroup` で開いた group の中に書かれる。top-level に出したければ wrapper が `WithGroup` を受けた時点で group 名を覚え、内側には `WithAttrs(request_id)` を group の外側で付ける (= `WithGroup` 前の handler に `WithAttrs` してから `WithGroup`) 必要がある。

## How to apply
- 「ctx の値を全行に付ける」wrapper を書くときは、`WithGroup` を使う呼び元が無いことを `grep -rl WithGroup` で確認するか、group 対応を wrapper に入れる。bloom は非テストコードに `WithGroup` の呼び元が無いので実害なし (logging.go の委譲だけ)。
- Reviewer は wrapper のテストに `WithAttrs` / `WithGroup` / ctx 無し / 無印 ctx の 4 経路を必ず入れ、group 経由は「行のどこかに id がある」で assert して挙動を報告に残す。
