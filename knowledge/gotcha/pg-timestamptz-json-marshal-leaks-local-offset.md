---
title: DB 往復した timestamptz の JSON 化はローカル offset を漏らす (Z 固定契約はフィールド単位で検証)
category: gotcha
tags: [go, pgx, timestamptz, rfc3339, wire-contract, json]
created: 2026-08-20
project: bloom
sources: [".designs/20260820-phase1-tech-foundation.md §6-1", "server/internal/store (P1 レビュー)"]
---

## Context
bloom P1 レビュー。設計は「時刻は全て UTC の RFC3339 (`Z` 固定)」を wire 契約にしていた (§6-1)。Reviewer が全 timestamp フィールドに Z サフィックス assert を入れたところ、G6 の `expires_at` は緑・A8 の `paused_at` は赤 (`2026-08-20T15:21:28+09:00`) と、**同一サーバー内でフィールドごとに割れた**。

## What
- Go でサーバー側が `clock().UTC().Add(...)` のように**計算して作った** time.Time は Z で出る。
- Postgres の timestamptz を pgx で **読み戻した** time.Time はサーバーのローカル TZ (JST) を持ち、`encoding/json` はそのまま `+09:00` で marshal する。
- つまり「Z 固定」は 1 箇所直せば済む話ではなく、**DB 往復するフィールド全部が個別に違反しうる**。テストが 1 フィールドの Z だけ見て緑でも、他のフィールドは平気で offset を吐く。

## Why
`time.Time` は location を内包し、`MarshalJSON` は location をそのまま RFC3339 の offset に写す。pgx は timestamptz をセッション TZ (通常サーバーの local) で返すため、「生成した時刻」と「読み戻した時刻」で location が食い違う。

## How to apply
- 実装側: JSON 境界で一元的に UTC 正規化する (DTO 詰め替え時に `.UTC()`、または custom marshaler)。store の scan 直後に `.UTC()` を徹底しても良いが、列追加のたびに漏れるので境界 1 箇所が安全。
- Reviewer 側: 「Z 固定」契約は**サーバー計算由来と DB 読み戻し由来の両方の標本**で assert する (どちらか片方だけだと系統的に素通しする)。timestamp を返す新規エンドポイントのテストには機械的に Z チェックを付ける。
