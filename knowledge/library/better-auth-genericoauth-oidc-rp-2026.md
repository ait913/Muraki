---
title: better-auth genericOAuth を OIDC RP として使う (1.7.7/1.7.12 実コード確認) — discovery は起動時 1 回・リンクに github_id フックは無い・refresh 失敗は潰される
category: library
project: global
tags: [better-auth, genericOAuth, oidc, rp, account-linking, refresh-token, discovery, end-session]
created: 2026-10-23
sources:
  - better-auth@1.7.7 / 1.7.12 dist/plugins/generic-oauth/index.mjs, dist/oauth2/link-account.mjs, dist/api/routes/{callback,account,sign-out}.mjs
  - projects/wasawasa/.knowledge/research-ais-pass-rp-20261023.md
model-era: sonnet-5
---

## Context
wasawasa を自前 OIDC IdP (AIS Pass) の RP にする事前調査で dist を全読した結果。

## What
- `genericOAuth({config:[{providerId, discoveryUrl, clientId, clientSecret, authentication:"basic", scopes, requireIdTokenVerification:true}]})`。独自 endpoint は無く、core の `/sign-in/social` と `/callback/:id` を使う (`signIn.social({provider})`)。discovery に `id_token_signing_alg_values_supported` があれば OIDC 扱い: `openid` 自動付与、`accountSubject` 既定 = `sub`、id_token を JWKS で検証 (aud=clientId, iss, nonce を state に束縛)、callback の `iss` を RFC 9207 で照合
- 既定の userinfo 取得は「id_token に sub と email があればそれ、無ければ userinfo endpoint」。userinfo の追加 claim (`github_id` 等) は `raw` として `mapProfileToUser` に届く。id_token の sub と userinfo の sub の一致は照合されない (自前 `getUserInfo` で確認する)
- **discovery は plugin `init` で 1 回だけ。失敗すると provider が登録されずプロセスが死ぬまで復旧しない (1.7.7)。1.7.12 は `genericOAuthPendingDiscovery` + before hook で要求時リトライ (10 秒 timeout)**。genericOAuth の他の差分は無い (`diff -r`)
- account 解決順: (providerId, accountId) → email 一致 (trustedProviders か email_verified、かつローカル user の emailVerified が必要) → 新規作成。**外部 claim で既存 user を選ぶフックは無い** (`selectedUser` は内部専用)。email が信用できない IdP では「`getUserInfo` 内で検証済み claim から account 行を先に `linkAccount`」(lazy link) が使える
- `/get-access-token` `/refresh-token` は refresh 失敗を一律 `FAILED_TO_*` に潰す (invalid_grant と一時障害を区別不能)、並行直列化も無い。IdP が refresh token をローテーションし再利用で family 無効にするなら、RP は自前 refresh + user 単位ロックが必要
- `/sign-out` は genericOAuth の `createEndSessionURL` を呼び、`{url, redirect:true}` を返す (id_token_hint=保存済み account.idToken、post_logout_redirect_uri は IdP 側登録と完全一致が必要)。client は既定で window.location 遷移
- 同一 providerId の `socialProviders.<id>` と併存はできない (generic が先頭で shadow)。別 id なら併存可

## Why
RP 側の認可正典を IdP に移すとき、リンク鍵・失効検知・起動時 discovery の 3 点で better-auth の既定が足りない。

## How to apply
- genericOAuth を使う設計では: 1.7.12 以上を使う / `getUserInfo` で sub 一致と必須 claim を検証 / email を信用しない IdP は lazy link / refresh は自前で直列化
