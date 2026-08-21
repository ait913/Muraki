---
title: clock 注入がトークン検証まで届かないと time-travel テストで認証が死ぬ
category: gotcha
project: bloom
tags: [clock-injection, jwt, integration-test, time-travel]
created: 2026-08-20
sources:
  - projects/bloom .designs/20260820-phase1-tech-foundation.md §15-1
  - bloom P3a Reviewer (TestPostDailyLimitJSTCalendarDay 初版の偽 fail)
---

## Context

時刻依存仕様 (日次上限・21:00 公開など) のテストは fakeClock を数時間〜数日シフトさせる。設計が「全 handler に clock を注入」と書いても、JWT ライブラリの exp/iat 検証は既定で実時間を使う。

## What

トークン**発行**は注入 clock、**検証**は実時間、という片側注入だと、clock を未来に飛ばした後に発行した access token が「未来発行 (iat > 実 now)」で 401 になる。テストは仕様と無関係な認証エラーで落ちる (偽 fail)。逆方向 (過去シフト) では即 exp 切れになる。

## Why

golang-jwt 等の `Parse` は `jwt.WithTimeFunc` を渡さない限り `time.Now()` で検証する。発行側だけ clock を差し替えても系全体の時間は一貫しない。

## How to apply

- 実装側: clock 注入を謳う設計なら、JWT 検証パーサにも同じ clock を渡す (`jwt.WithTimeFunc(clock)`)。
- テスト側 (実装を直せない/直さない場合): 時刻シフトを跨ぐテストでは、実時間基準で exp に余裕を持たせた自作トークン (テスト秘密鍵で HS256 直署名) を使い、認証を clock シフトから切り離す。
- Reviewer の切り分け: 「シフト直後の最初の認証付きリクエストが 401」はまずこれを疑う (仕様バグではなくハーネス×片側注入)。
