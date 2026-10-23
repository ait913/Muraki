---
title: better-auth 1.7.12 を「GitHub + TOTP 必須の OIDC IdP」にする時の 4 つの関門 (コールバック内 authorize の迂回、refresh がセッションを見ない、HTTP 面の許可リスト、理由コード付きホワイトリスト)
category: pattern
tags: [better-auth, oauth-provider, oidc, idp, totp, two-factor, social-login, refresh-token, validateUserInfo, genericOAuth, onRequest]
created: 2026-10-23
project: global
sources:
  - 実コード: npm pack better-auth@1.7.12 @better-auth/core@1.7.12 @better-auth/oauth-provider@1.7.12 の dist を読んだ (2026-10-23)
  - Muraki/projects/ais-pass/.designs/20261023-phase1-pass-core.md (§5, §9)
---

## Context
AIS Pass (招待制、GitHub OAuth + TOTP 必須、OIDC provider) の設計で、better-auth の既定経路に「社会ログイン後の第二要素」が無いことを前提に、2FA 未完了のセッションから code / token が漏れる経路を dist で洗った。

## What
1. **`@better-auth/oauth-provider` は `/sign-in/social` の本文に `oauth_query` があると、コールバックでセッション cookie を付けた直後に after hook の中で `runOAuth2Authorize` を実行する** (`hooks.after` の matcher = 応答に session cookie)。この authorize は `/oauth2/authorize` の path を通らないので、そこに置いた before hook (2FA 判定・許可表) が効かない。`oauthProviderClient()` はブラウザの query から `oauth_query` を自動で本文に足す
2. **refresh grant (`handleRefreshTokenGrant`) はセッションの存在も BAN も見ない**。`oauthRefreshToken.sessionId` はセッション削除で SET NULL になるだけ。`admin.banUser` / セッション失効後も refresh が通る。code 交換 (`handleAuthorizationCodeGrant`) はセッションの存在と期限だけ見て、許可・client 状態は見ない。code は `verification` に `identifier = storeTokens.hash(code)`、`value = JSON {type:"authorization_code", userId, sessionId, query, ...}` で保存され既定 600 秒 (`codeExpiresIn`)
3. `storeTokens` は `{ hash(token, type) }` を受けるので、自分の hash 関数を渡せば before hook で提示された refresh token の行を引ける
4. router の `onRequest` (plugin の `onRequest`) は HTTP 経由にだけ走り、`auth.api.*` の server 呼び出しには走らない。`disabledPaths` も router だけ (`api/index.mjs`)
5. core の `user.validateUserInfo` が `{ error: code }` を返すと、OAuth コールバックは `errorCallbackURL?error=<code>` へ戻す。`databaseHooks.user.create.before` が `APIError(..., { code })` を投げても同じく `?error=<code>`。throw は `validation_failed` で fail-closed
6. `socialProviders.github` は token endpoint が固定文字列でテストのスタブに向けられない。`genericOAuth` に providerId `github` で `authorizationUrl` / `getToken` / `getUserInfo` / `accountSubject` を書けば core の `/callback/github` をそのまま使える
7. `addOAuthServerContext()` (better-auth/api) を `/sign-in/social` の before hook で呼ぶと、クライアントが偽造できない値をコールバックまで運べる (`getOAuthState().serverContext`)。招待 id の受け渡しに使える
8. admin plugin の `user.create.before` は `{ role: defaultRole, ...user }` なので、自分の hook が返した role が順序に関係なく勝つ

## Why
twoFactor plugin は credential サインイン (`/sign-in/email` 等) 専用で、IdP 化した時の「第二要素前の半認証状態」はアプリが表現するしかない。表現した瞬間に、provider がアプリの判定点を通らずに code / token を出す経路 (1, 2) が穴になる。

## How to apply
- 半認証は `session.additionalFields.twoFactorVerifiedAt` (nullable) + `cookieCache` 無効で表し、判定は毎回 DB
- `hooks.before` で `/oauth2/consent` `/oauth2/continue` 以外の path の本文に `oauth_query` があれば throw (1 を塞ぐ)。クライアントに `oauthProviderClient()` を入れず、ログイン画面が authorize URL を標準パラメータだけで組み直して `next` に持つ
- code 交換・refresh・userinfo の全入口 (before hook) で、トークン行 (code は `verification`、`value` JSON に `sessionId`) を自分の hash で引き、「**発行元セッションそのもの**が生存 + 2FA 済み + 非 BAN + 許可表 + client 有効」に束縛する (2 を塞ぐ)。行が引けなければ provider に回さず拒否 (fail-closed)。「同じユーザーに生きたセッションが 1 本でもあれば通す」型の緩和は失効したセッションのトークンを生き返らせるので入れない。失効時はトークン行を消さずに残し、使用時に理由付きで拒否・記録してから消す (先に消すと「不明」としか言えない)。introspect はゲートを通らない入口になるので閉じる
- `/api/auth` の HTTP 面は自前 plugin の `onRequest` で許可リスト化 (admin plugin・client CRUD・link-social 等を全部閉じる)。server からの `auth.api.*` は影響を受けない
- ホワイトリストは `getUserInfo` の null (理由が `unable_to_get_user_info` 1 種に潰れる) ではなく `validateUserInfo` の `{ error }` で返す。消費を伴う招待は `user.create.before` の原子的 UPDATE で最後にもう一度締める
- twoFactor plugin を `allowPasswordless: true` で足し戻さない (2FA 未完了セッションが `/two-factor/disable` を叩ける)
