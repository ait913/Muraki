---
title: better-auth bearer は raw DB session token を受け付けない (signed token / set-auth-token 経由が必須)
category: gotcha
tags: [better-auth, bearer, auth, hono, native, ios]
created: 2026-06-08
project: atender
sources:
  - "atender .designs/20260608-ios-foundation.md §8.1 / §8.4"
  - "apps/api/tests/ios-api.test.ts (Reviewer 生成)"
---

## Context
Atender iOS 土台で web の Cookie session に加えネイティブ用に better-auth `bearer()` plugin を足し、`Authorization: Bearer <token>` で `/api/me` を通す設計 (§8.1)。Reviewer が §8 だけからテスト生成して実行したら、Bearer→/api/me が 401 で落ちた。

## What
- テストヘルパ `createSessionCookie` は `Session.token = <hex24>.<hex32>` の **raw 文字列を DB に直書き**し、それを Cookie 値として送る。Cookie 認証はこの raw token で 200 通る (このアプリは署名検証で弾いていない or getSession が token 一致で解決)。
- ところが同じ raw token を `Authorization: Bearer` で送ると 401。診断の結果:
  - `POST /api/auth/sign-in/social` レスポンスに **`set-auth-token` ヘッダが付かない**。
  - `/api/auth/get-session` に Bearer (raw も signed `<token>.<hmac>` も) を付けても **200 / body=null** (session 解決されず)。
- → bearer plugin が**未導入 (または Authorization を解決していない)** ことを示す。token 形式の問題ではない (raw / first-segment / signed すべて失敗)。

## Why
- better-auth `bearer()` は「Authorization ヘッダを Cookie 同等に解決する」プラグイン。**未導入だと getSession は Authorization を一切見ない** → middleware が null → 401。
- さらに罠: bearer が解決するトークン形式と、§8.4 の中継 (`/api/auth/native/callback`) が fragment に載せるトークン形式が**一致している必要がある**。テストでは中継が **raw DB token** を埋めて通った (Reviewer 側が raw 前提で書いたため)。bearer 導入後に bearer が signed token しか受けないと、中継の raw token を native が Bearer で送って再び 401 になる二重事故が起きうる。中継が emit する値と bearer が accept する値を**同一の生成経路 (set-auth-token / better-auth API)** に揃えること。

## How to apply
- Bearer 認証テストは「sign-in レスポンスの `set-auth-token` 存在」「`/api/auth/get-session` が Bearer で session を返す」をまず確認すると、plugin 導入有無を token 形式問題と切り分けられる。
- 実装側 (Developer): `bearer()` を plugins に追加。中継ハンドラ (§8.4) が fragment に載せる token は **bearer が後で accept できる形式**で出す (DB raw token を直に出さず、better-auth の token 発行経路を通す or set-auth-token を流用)。
- 設計側 (Architect): §8.1 が「accept するトークン形式」と §8.4 が「emit するトークン形式」を**明示的に同一と書く**。raw DB token を native が持ち回る前提なら、bearer をその形式で解決できるか先に検証ポイントとして残す。
