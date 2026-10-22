---
title: better-auth 1.7.12 の twoFactor は社会ログインを通さない (hook は /sign-in/email|username|phone-number だけ) — GitHub + TOTP は自前の「2FA 未完了セッション」が要る。admin / 招待 / 許可表フックの現存一覧
category: library
project: global
tags: [better-auth, two-factor, totp, admin, github-oauth, social-sign-in, validateUserInfo, accountSubject, invitation]
created: 2026-10-23
sources:
  - https://raw.githubusercontent.com/better-auth/better-auth/main/docs/content/docs/plugins/2fa.mdx
  - https://raw.githubusercontent.com/better-auth/better-auth/main/docs/content/docs/plugins/admin.mdx
  - https://raw.githubusercontent.com/better-auth/better-auth/main/docs/content/docs/plugins/organization.mdx
  - https://raw.githubusercontent.com/better-auth/better-auth/main/docs/content/docs/plugins/generic-oauth.mdx
  - 実コード: npm i better-auth@1.7.12 の dist (plugins/two-factor/index.mjs, verify-two-factor.mjs, utils/validate-user-info.mjs, @better-auth/core social-providers/github.mjs) を grep (2026-10-23)
  - https://github.com/advisories/GHSA-xg6x-h9c9-2m83 (CVE-2026-67337, cookieCache と 2FA)
model-era: fable-5.1
---

## Context

AIS Pass (GitHub OAuth + TOTP 必須、招待制、owner/admin/member) の設計前に、better-auth 1.7.12 の `twoFactor` / `admin` / 招待 / サインイン拒否フックを dist と docs で確認した (2026-10-23)。

## What

- **`twoFactor` の sign-in hook matcher は `path === "/sign-in/email" | "/sign-in/username" | "/sign-in/phone-number"` と `/two-factor/*` のみ** (dist grep)。GitHub 等の社会ログイン callback は 2FA を経ずに完全なセッションを作る。docs も「OAuth / magic link / passkey は gated されない、custom hook が要る」と明記。全員必須にする option も無い。
- `/two-factor/verify-totp` (`verify-two-factor.mjs`): セッション無し → 署名 cookie `two_factor` → verification 表 → user → `valid()` で新規セッション作成。**セッション有り → `valid()` はトークンを返すだけでセッション状態は変えない**。つまり社会ログイン後に叩いても「2FA 済み」の印は付かない。
- TOTP 秘密は `symmetricEncrypt({ key: ctx.context.secretConfig, data: secret })` で BETTER_AUTH_SECRET により暗号化保存。バックアップコードは 1.7.12 の dist で既定 `storeBackupCodes: "encrypted"` (docs の "plain" は古い)。
- `enable` / `disable` / `get-totp-uri` / `generate-backup-codes` は `password` 必須。**`allowPasswordless: true` で OAuth のみのユーザーでも省略可** (`shouldRequirePassword` が credential account の有無で判定)。
- ロックアウト既定: 10 回失敗で 900 秒 (TOTP / OTP / backup 共通)。`trustDevice` は 30 日。
- 管理者による 2FA リセット API は無い (`admin` plugin は twoFactor に触らない)。`twoFactor` 行削除 + `user.twoFactorEnabled=false` + `revokeUserSessions` を自前で。
- `admin`: `banUser` はサインイン拒否 + 全セッション失効。`createAccessControl` + `ac.newRole` で owner / admin / member 等の独自ロール可、`adminRoles` に複数指定可。`listUserSessions` / `revokeUserSession` (token 単位) / `revokeUserSessions` (ユーザー単位) / `impersonateUser` あり。
- 招待: `organization` plugin の招待は `email` 必須で accept は「セッションの email 一致」判定。GitHub numeric id で縛る用途には合わない (自前)。
- GitHub の不変 id: `account.accountId` = `provider.accountSubject` = `({ profile }) => profile.id` (`@better-auth/core/dist/social-providers/github.mjs`) を `String()` したもの。
- サインイン拒否フック (現存 3 つ): `socialProviders.<id>.getUserInfo` で `null`、**core の `user.validateUserInfo({ user, source }, ctx)`** (`create-user` / `link-account` / `sign-in` で呼ばれ、`{ error }` 返却で 403、throw も fail-closed)、`databaseHooks.user.create.before`。
- CVE-2026-67337: `session.cookieCache` 有効時に 2FA 前のセッションが有効扱い (1.4.9 未満で修正済)。自前の「2FA 未完了セッション」を作る場合も同じ構造になるので cookieCache を切るか判定を DB 列に置く。

## Why

`twoFactor` は credential サインインの第二要素として設計されており、社会ログインの後段に差し込む口が無い。社会ログイン + TOTP 必須は「半認証セッション」をアプリが表現する必要がある。

## How to apply

- `session.additionalFields` に `twoFactorVerifiedAt` (nullable) を持ち、社会ログインの callback 後 (`databaseHooks.session.create` または `hooks.after` の `/callback/:id`) は null。自前 endpoint で `twoFactor.secret` を `symmetricDecrypt` して TOTP 検証 → 埋める。管理画面 guard と `oauthProvider` の `/oauth2/authorize` を受ける `hooks.before` で null を拒否。`session.cookieCache` は使わない。
- TOTP 登録 UI は plugin の `/two-factor/enable` (`allowPasswordless: true`) + `/two-factor/get-totp-uri` + `verify-totp` (登録確認) を流用できる。
- 許可表外の GitHub アカウントは `getUserInfo` で null (wasawasa 流儀) か `user.validateUserInfo` で 403 にし、`profile.id` で照合する。
