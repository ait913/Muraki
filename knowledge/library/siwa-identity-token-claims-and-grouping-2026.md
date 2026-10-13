---
title: "Sign in with Apple: identity token のクレーム実仕様 (email は毎回 / 名前は初回のみ / email_verified は string|bool) と App ID グループ化の副作用"
category: library
project: global
tags: [sign-in-with-apple, siwa, identity-token, email, private-relay, app-grouping, asc]
created: 2026-10-13
sources:
  - https://developer.apple.com/documentation/signinwithapplejs/authorizationi/id_token
  - https://developer.apple.com/documentation/signinwithapple/authenticating-users-with-sign-in-with-apple
  - https://developer.apple.com/documentation/signinwithapple/verifying-a-user
  - https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens
  - https://developer.apple.com/documentation/signinwithapple/communicating-using-the-private-email-relay-service
  - https://developer.apple.com/help/account/configure-app-capabilities/group-apps-for-sign-in-with-apple
  - "ASC API GET /v1/bundleIds/{id}/bundleIdCapabilities (bloom, 2026-10-13)"
---

## Context
bloom で「初回サインインが 426 で止まり氏名が失われて名無しユーザーができた」事故の後、`users.email` 追加と名前の堅牢化を設計する前に Apple 一次ソースで確認した (2026-10-13)。

## What
1. **id_token クレーム** (REST の id_token 参照先は `signinwithapplejs/authorizationi/id_token`): `iss sub aud iat exp nonce nonce_supported email email_verified is_private_email real_user_status transfer_sub org_id scopes`
2. **`email_verified` / `is_private_email` は string ("true"/"false") でも Boolean でも来る**と明記。型付き struct で `bool` 受けは parse 失敗しうる → 両対応のカスタム型
3. **email は 2 回目以降も identity token に毎回入る** (email scope 要求時)。**名前 (fullName) は初回認可のみ**で identity token には一切入らない (端末 UI → アプリ直渡し)。`real_user_status` も初回のみ。Managed Apple Account (ASM) では email が空のことがある
4. **refresh_token grant (`/auth/token`, `grant_type=refresh_token`) は `id_token` + `access_token` を返す** (refresh_token は返らない)。refresh 検証は **1 日 1 回まで** (超えると throttle)。refresh 由来の id_token に `email` が入るかはドキュメントに明記なし (probe 推奨)
5. **Private relay**: `@privaterelay.appleid.com` / `@private.icloud.com` / `@icloud.com`。同一 Team 内の全アプリで同じ relay アドレス。1 アドレス 1 日 100 通。送信には Services → "Sign in with Apple for Email Communication" に送信ドメイン/アドレスを登録 + SPF (and/or DKIM) 必須
6. **App ID グループ化** (ASC API では `APPLE_ID_AUTH_APP_CONSENT: PRIMARY_APP_CONSENT | RELATED_APP_CONSENT` として見える。グループ先の primary は API に出ない): グループ内で同意は 1 回だけ、`sub` も Team 内共通。→ **dev アプリ (secondary) で先にサインインした Apple ID は prod 初回でも fullName が nil**。再度名前を貰うには端末の 設定 → Apple Account → Sign in with Apple → 該当アプリ → 停止

## Why
「初回だけ名前が来る」は知られているが、「dev 側の初回が prod の初回を消費する」「email_verified が文字列で来る」「refresh grant でも id_token が返る (= email backfill の入口)」は設計時に見落としやすく、どれも実装後に直すと migration/データ修復が要る。

## How to apply
- 名前は (a) クライアントが credential の fullName をサーバー受理まで保持、(b) サーバーは既存行が既定名のときだけ上書き、の両方を入れる
- email を保存するなら Verify 段で identity token から取る (code 交換の id_token は不要)。既存ユーザーの backfill は refresh grant で 1 回走らせる (1 日 1 回制限内)
- dev/prod をグループ化している PJ は実機ゲート手順に「Sign in with Apple の停止で初回状態に戻す」を書く
