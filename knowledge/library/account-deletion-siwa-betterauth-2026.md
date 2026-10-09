---
title: アカウント削除 (Guideline 5.1.1(v)) — Sign in with Apple の revoke と better-auth 1.6 deleteUser の実仕様
category: library
project: global
tags: [app-review, account-deletion, sign-in-with-apple, better-auth, prisma, sqlite]
created: 2026-10-09
sources:
  - https://developer.apple.com/support/offering-account-deletion-in-your-app/
  - https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple
  - https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens
  - https://developers.google.com/identity/protocols/oauth2/web-server (Revoking a token)
  - better-auth 1.6.11 実コード (dist/api/routes/update-user.mjs, dist/plugins/bearer/index.mjs)
---

## Context
Atender (iOS, better-auth + Prisma/SQLite, Apple/Google/Magic Link) の初回審査前に、アカウント削除の要件と実装部品を一次ソースで確認した記録 (2026-10-09)。

## What
1. **要件**: アカウント作成を持つアプリは「アプリ内で削除を開始」できること。一時無効化のみは不可。メール/電話/チャット等のサポート経由のみは不可 (規制業種 5.1.1(ix) 除く)。再認証・確認ステップ・メールコード確認は可 (「不必要に困難」はNG)。完了に時間がかかるなら利用者に伝える。猶予期間の規定は無い
2. **SIWA**: Apple FAQ は「`revoke` REST API を**使うべき**」(should)。TN3194: revoke には有効な refresh/access token が必要。無い場合も削除要求自体は履行必須。Apple 公式は「審査で revoke 未実施は reject」とは書いていない (should 止まり)
3. **ネイティブ idToken ログインでは refresh token が手に入らない**。better-auth の `sign-in/social {idToken}` 経路は `account.accessToken = body.idToken.accessToken` しか保存せず refresh は捨てる。実 prod DB でも apple account の access/refresh/id は全 NULL。revoke するには authorizationCode (5 分・1 回限り) をサーバーで `/auth/token` に交換するしかない (iOS が `credential.authorizationCode` を別途送る必要)
4. **client_id / client_secret**: revoke・token とも `client_id` は認可リクエスト時の識別子 (ネイティブ=Bundle ID、Web=Services ID)。既存 `buildAppleClientSecret` (Team/Key/p8) は `clientId` 引数を Bundle ID にすれば流用可。**実測**: 本番 Coolify の鍵で `sub` を Bundle ID / Services ID の両方にして bogus code を `/auth/token` へ → どちらも `invalid_grant` (= client 認証は通る。`invalid_client` ではない)。revoke は bogus token でも 200 を返すのでこの判別に使えない
5. **Google**: `POST https://oauth2.googleapis.com/revoke` (form `token=`, access/refresh どちらでも, 成功 200 / 失敗 400)。公式は「ユーザー退会時の programmatic revoke は重要」と推奨するが必須とは書かない。**revoke は同一 GCP プロジェクトの全クライアントの全スコープを失効させる**
6. **better-auth 1.6.11 `user.deleteUser`**: `enabled / sendDeleteAccountVerification / beforeDelete(user, request) / afterDelete / deleteTokenExpiresIn`。エンドポイントは `POST /delete-user` (body は JSON 必須、`{}` 可: `callbackURL? password? token?`)。`sensitiveSessionMiddleware` (cookie cache 無効で DB 照合)。`sendDeleteAccountVerification` 未設定なら**即削除**。その場合 `password` 無しだと **session.createdAt から freshAge (既定 24h) 超過で 400 SESSION_EXPIRED** (OAuth のみユーザーは password 経路が使えない) → 30 日セッションの iOS ではほぼ必ず踏む。`session.freshAge: 0` で無効化、またはメール確認フローにする
7. 削除順は sessions → accounts → user (adapter.deleteUser)。`beforeDelete` 時点では account はまだ残る (トークン取得はここ)。Bearer: raw token を `Authorization: Bearer` で送れば bearer plugin が署名して cookie 化するので `/api/auth/delete-user` も Bearer で叩ける
8. **Prisma 6 + SQLite は `PRAGMA foreign_keys = 1` が既定で効く** (実測、`relationMode` 未指定=foreignKeys)。onDelete: Cascade は本当に連鎖する。実測: 作成者を `user.delete` → 作成した Room が消え、他メンバーの RoomMembership も消えた
9. **nginx `try_files $uri /index.html` の SPA で静的法務ページ**: `public/privacy/index.html` は `/privacy/index.html` でのみ配信され、`/privacy` と `/privacy/` は**どちらも SPA の index.html** (実測 docker nginx:alpine)。`public/privacy.html` → `/privacy.html` は素通りで配信される

## Why
「設定に削除ボタンを足して `DELETE /api/me`」の見積もりを崩す事実が 3 つある: (a) ネイティブ SIWA は refresh token を保存していないので revoke は iOS 側の変更を伴う、(b) better-auth 既定の freshAge で OAuth ユーザーは削除に失敗する、(c) FK Cascade が他人のデータ (作成ルーム等) を巻き込む。

## How to apply
- 設計前に「Apple トークンを保存しているか」を `Account` の実データで確認する (idToken ログインは NULL)
- 削除で他ユーザーに波及する Cascade を `onDelete` 全列挙で洗い、波及させるか SetNull/移譲するかを先に裁定する
- 法務ページは `public/<name>.html` (拡張子付き URL) が nginx 設定変更ゼロで最小。URL を ASC に登録するなら実 `curl -I` で 200 + Content-Type を確認
