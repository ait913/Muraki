---
title: fake 時計で絶対日付のテストを書くと JWT の exp が実時刻で落ちる / `if false {` の変異はビルド失敗を「kill」と誤認する
category: gotcha
tags: [go, testing, fake-clock, jwt, mutation-testing, bloom]
created: 2026-11-04
project: bloom
sources: [bloom 接近通知の日窓化 Reviewer (2026-11-04)]
---

## Context

bloom の統合テスト harness は `fakeClock` (実時刻 + offset) を使う。日跨ぎ (JST 0 時) のような「絶対日付」が仕様のテストでは、時計を `2026-11-04T14:59:59Z` のような固定日付に合わせたくなる。変異テスト (負のコントロール) では `if cond {` を `if false {` に差し替える手が定番。

## What

1. 時計を実時刻より過去の固定日付に戻すと、サーバーの access JWT 検証が (ライブラリが exp を実時刻で見るため) 全リクエスト 401 になる。`auth.Service.IssueAccessAt(uid, fakeNow)` で再発行した token も同じ理由で落ちる。症状は `TOKEN_EXPIRED` / `UNAUTHENTICATED` で、テスト対象の挙動とは無関係に見える。
2. `if false {` に変異させると、ブロック内でしか使っていない変数が「declared and not used」になって**ビルドが落ち**、`go test` が非 0 で終わる。変異スクリプトは「テストが赤くなった = kill」と数えるので、実際には何も検証していない偽の kill になる。

## Why

1. JWT ライブラリは `jwt.WithTimeFunc` を渡さない限り `time.Now()` で exp を比べる。harness の時計はサーバー側のロジックにしか効かない。
2. 変異の目的は「ガードを弱める向き」に 1 箇所だけ変えること。コンパイルエラーは別の失敗。

## How to apply

- 絶対日付の標本は「実時刻の 2 日後の日付」に置く (`pdBase = 今日 00:00Z + 2 日`、T0 = +3h、M− = +14:59:59、M+ = +15:00)。fake 時計は前向きにしか動かさない。ユーザーは時計を T0 の少し前にしてから作る。access は `userLong` と同じ「実時刻 + 72h の HS256」を使う (`hs256Token`)。
- 日番号の KAT (固定日付) は時計に依存しない純関数 (Go `DayJST` / Dart `LocationTokens.day`) のテストで固定日付のまま検証する。
- 変異は `cond` → `cond && false` の形にして変数の未使用を避ける。変異スクリプトは出力に `build failed` を含むかを必ず数え、含んだら無効扱いにする。
- 停止 (BAN) を fixture にするとき、`user_bans` の直挿入では認証層は止まらない。admin API (`newAdminHarness` の `mustBan`) を通す。
