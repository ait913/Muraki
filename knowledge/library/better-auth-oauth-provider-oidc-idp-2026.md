---
title: better-auth 1.7.7 で自前 IdP (OIDC) を立てる — oidcProvider は消滅、mcp() = oauthProvider で max_age/auth_time まで実装済 (2026-10 実コード確認)
category: library
project: global
tags: [better-auth, oidc, oauth-provider, idp, rp, pkce, max_age, auth_time, jwks, admin-sso]
created: 2026-10-10
sources:
  - https://raw.githubusercontent.com/better-auth/better-auth/main/docs/content/docs/plugins/oauth-provider.mdx
  - https://raw.githubusercontent.com/better-auth/better-auth/main/docs/content/docs/plugins/mcp.mdx
  - 実コード (npm i better-auth@1.7.7 @better-auth/oauth-provider@1.7.7 @better-auth/mcp@1.7.7 の dist を grep)
model-era: sonnet-5
---

## Context
wasawasa (better-auth 1.7.7 + `mcp()`) を管理系サービスの OIDC IdP にできるかの調査。

## What
- `better-auth@1.7.7` の `dist/plugins/` に `oidc-provider` も旧 `mcp` も **存在しない**。IdP は `@better-auth/oauth-provider` (`oauthProvider()`) が唯一。
- `@better-auth/mcp` の `mcp()` は `oauthProvider()` そのもの (戻り型が `ReturnType<typeof oauthProvider>`)。**同一 auth に `oauthProvider()` を別途足せない** (公式 doc 明記)。`oauthProvider` の全オプションは `mcp()` 側に渡す。
- OIDC: `openid` scope で ID token / UserInfo / RP-initiated logout (`/oauth2/end-session`、`enable_end_session: true` の client のみ)。code + S256 PKCE のみ (plain 不可)、redirect_uri は exact match (native の loopback のみポート可変)、全 authorize 応答に RFC 9207 `iss`。`/.well-known/openid-configuration` あり。署名は `jwt()` plugin (JWKS `/jwks`、EdDSA 既定。`keyPairConfig.alg` は EdDSA/ES256/ES512/PS256/RS256 のみ)。
- **Back-Channel Logout は 1.7.12 で実装済** (2026-10-23 dist grep: `backchannel_logout_uri` / `logout+jwt`)。client に `backchannel_logout_uri` (public https のみ) を登録すると、セッション終了時に `typ: logout+jwt` の Logout Token を RP ごと 5 秒 timeout・**再送無し**で送る。`jwt()` 必須 (`disableJwtPlugin` だと登録が `invalid_client_metadata`)。`advanced.backgroundTasks.handler` で遅い RP を待たずにサインアウトできる。Front-channel logout は無い。
- `max_age` (`session.createdAt` からの経過で判定、0 は常に再認証) と `prompt=login|none|consent|select_account|create` を authorize が実装。ID token に `auth_time` (= session.createdAt)、`acr:"0"` 固定。`customIdTokenClaims({user,scopes,metadata})` で claim 追加 (iss/sub/nonce 等は剥がされる)。
- クライアント静的登録は server 専用 `auth.api.adminCreateOAuthClient` (`skip_consent`, `enable_end_session` は admin 専用フィールド)。`cachedTrustedClients` は CRUD 禁止になる。
- DCR は opt-in (`allowDynamicClientRegistration` + `allowUnauthenticatedClientRegistration`)。wasawasa は MCP 用に ON → IdP を共用すると誰でも client を登録でき、その client 向け ID token も発行できる (aud = その client_id)。RP は **aud/iss/nonce を必ず検証**。
- **jwt の alg 切替は設定変更だけでは効かない** (1.7.12 実コード・2026-10-24): 署名鍵は `getLatestKeyByAlg(設定alg) ?? getLatestKey()` なので、旧 alg の生存鍵がある間は旧 alg で署名され続ける。強制は旧 `jwks` 行の `expiresAt` を過去にする (JWKS には gracePeriod 分残る)。discovery の `id_token_signing_alg_values_supported` は `[keyPairConfig.alg, ...keyPairConfigs の alg]`。RP の `genericOAuth` は **起動時 discovery の alg 一覧を `algorithms` に固定し再取得しない**ので、alg を変える前に extras で advertise → RP 再起動 → 切替の 2 段階にする。`jwks` の `alg` が NULL の行は「現設定 alg」扱いになる。client は登録した `token_endpoint_auth_method` 以外では認証できない (`invalid_client`)。Cloudflare Access generic OIDC は EdDSA 非対応 (RS256/RS512/PS512/ES256/ES384/ES512)。詳細: projects/ais-pass/.knowledge/research-cloudflare-access-oidc-20261024.md
- 既定 TTL: access 1h / id 10h / refresh 30d / code 10m。`idTokenExpiresIn` で短縮可。

## Why
管理系の認証基点を既存の better-auth に寄せるとき、別 plugin を足せない・DCR が開いている・Org 在籍チェックが issuance 経路に無い、が設計の前提になる。

## How to apply
- 管理系 RP は専用 client (confidential or public+PKCE、`skip_consent`、exact redirect_uri) を admin API で静的登録。RP は `openid-client` v6 (`npm view` で 6.8.8) 等で discovery + PKCE + state + nonce + `iss` 検証。
- 破壊操作の step-up は `max_age=0`/`prompt=login` + ID token の `auth_time` 検証。**実測 (2026-10-10、1.7.7 + memory adapter + email サインイン)**: セッションありでも `loginPage?…&sig=…` に 302 → `oauth_query` 付きでサインインし直すと新セッションが作られ、続きの code の ID token の `auth_time` = 新セッション時刻 (flow 開始より後)。通常の authorize の `auth_time` は既存セッションの作成時刻のまま。再認証の強度は上流 (GitHub) のログイン状態次第
- **loginPage 側の罠**: 「セッションがあれば next へ redirect」するサインイン画面だと step-up が成立しない。クエリに `sig` があるときは redirect せず画面を出す (wasawasa 20261010 doc §4-8)
- 実測: `adminCreateOAuthClient` は **セッションの headers が要る** (無いと 401)。`metadata` は `customIdTokenClaims({metadata})` にそのまま届く。予約 claim (`iss`/`auth_time` 等) を返すと剥がされる。`idTokenExpiresIn: 300` で `exp−iat=300`、alg は EdDSA、`offline_access` を許可しない client には refresh token が出ない。DCR (`/oauth2/register`) の本文に `metadata` を付けても保存されない
- `customIdTokenClaims` は client_id を受け取らない (`{user, scopes, metadata}` だけ)。client ごとの判定は metadata にサーバー秘密の HMAC (binding) を入れて照合する。**authorize 時に user と client_id の両方を受け取るフックは 1.7.12 にも無い** (`postLogin.shouldRedirect` / `selectAccount.shouldRedirect` / `postLogin.consentReferenceId` は `{headers, user, session, scopes}` のみ)。client × user の許可表は wasawasa の `hooks.before` (`/oauth2/authorize` `/oauth2/consent` `/oauth2/continue` で `client_id` を query / body / 署名付き `oauth_query` から読む) で強制する
- 未検証: `customIdTokenClaims` が throw した時の応答 (throw せず `{}` を返す設計にすれば不要)
- memory adapter で probe するときは model 名を事前に配列で用意する (`oauthResource` 等が無いと init で落ちる。Proxy は structuredClone できず不可)
