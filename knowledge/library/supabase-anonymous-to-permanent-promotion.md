---
title: Supabase の匿名アカウントを永続アカウントに昇格させる (user id は保たれる / is_anonymous は 2 段で落ちる)
category: library
project: global
tags: [supabase, auth, anonymous, jwt, claims, otp, gotcha]
created: 2026-07-30
sources:
  - https://supabase.com/docs/guides/auth/auth-anonymous
  - OMATASE 本番プロジェクト (hrdvkqunqbysbygbgcck) への実測 2026-07-30
---

## Context

「ゲストは名前だけで参加、後からメール登録して永続アカウントにする」を作りたいとき。

自前トークン (アプリが HS256 で発行する類) でゲストを表すと、機種変で締め出される / 同じ人が
複数メンバーとして重複する / 失効設計を自分で書く、という問題を全部抱える。Supabase の
**匿名アカウント**を使えば、ゲストも通常の JWT を持つ 1 ユーザーになる。

## What

### 有効化

既定で **無効**。Management API で開ける (ダッシュボードでも可):

```sh
curl -sS -X PATCH -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H "Content-Type: application/json" \
  "https://api.supabase.com/v1/projects/$REF/config/auth" \
  -d '{"external_anonymous_users_enabled":true}'
```

### 匿名サインイン

`supabase.auth.signInAnonymously()` = **`POST /auth/v1/signup` に空 body**。
curl で直接確かめられる (anon key だけで通る):

```sh
curl -sS -X POST -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  "https://$REF.supabase.co/auth/v1/signup" -d '{}'
```

### ★ 昇格しても user id は変わらない

`supabase.auth.updateUser({ email })` → 届いた OTP を `verifyOtp` で検証。
**`id` は最初から最後まで同一**。これが効くのは、アプリ側のテーブルが `user_id` を
外部キーに使っている場合に **1 行も書き換えずに済む**こと。過去の参加履歴が繋がったままになる。

`linkIdentity` は使わない — あれは OAuth の複数 identity を紐づける API で
`security_manual_linking_enabled` を要求する (既定 `false`)。email 昇格には `updateUser` で足りる。

### ★★ `is_anonymous` は 2 段で落ちる (ここが罠)

OMATASE 本番で実測した一周:

| 段                             | `id`   | `is_anonymous` | `email` / `new_email`                 |
| ------------------------------ | ------ | -------------- | ------------------------------------- |
| 匿名サインイン直後             | `X`    | **`true`**     | `email = ''` (**null ではない**)      |
| `updateUser({ email })` 直後   | 同じ   | **`true`**     | `email=''` / `new_email` に入る       |
| OTP 検証後                     | 同じ   | **`false`**    | `email` が入る / `identities=[email]` |

つまり `updateUser` は**メールを `new_email` に積むだけで、まだ匿名**。

**さらに: 検証後も古いアクセストークンは `is_anonymous: true` を持ち続ける。**
claim は JWT に焼き込まれているので、サーバーが claim で認可を分けている場合
**「メール登録は成功したのに操作が 403 のまま」**になる。

→ **`verifyOtp` が返す新しいセッションを使う** (古いトークンを使い回さない)。

### JWT の形

- **`alg: ES256`** + `kid`。**匿名ユーザーも通常の非対称 JWKS 検証経路をそのまま通る**。
  サーバー側に匿名専用の検証分岐は要らない
- `role` / `aud` はどちらも `authenticated` — **通常ユーザーと区別できない**。
  区別は `is_anonymous` claim だけ

## Why

- **匿名かどうかの判定をクライアントに任せられない。** `role` が `authenticated` なので、
  RLS や API で「ログイン済か」を見ても匿名ユーザーは通る。`is_anonymous` を明示的に見る必要がある
- **`is_anonymous` の遅延が「サーバーは正しいのに壊れて見える」バグを作る。** サーバーは
  受け取った JWT の claim どおりに動いているだけなので、ログを見ても異常が無い

## How to apply

1. 匿名ユーザーに禁じたい操作は **サーバー側で `is_anonymous` を見て弾く**。
   クライアントの分岐だけに頼らない (`role`/`aud` では判別できない)
2. 昇格フローの UI は **`verifyOtp` の戻りセッションに差し替える**まで完了扱いにしない
3. `email` は匿名時 **空文字列**。`null` チェックだけ書くとすり抜ける
4. 匿名アカウントは**溜まる**。掃除の起点を決めておく (イベントのアーカイブ等)。
   `DELETE /auth/v1/admin/users/{id}` は service_role キーで叩ける
5. **プローブで検証できる。** メールを読まずに一周確認する手順:
   - `POST /auth/v1/signup` に `{}` → JWT の payload を base64 デコードして claim を見る
   - `PUT /auth/v1/user` に `{"email":...}` (匿名の access token で) → `id` と `new_email` を確認
   - `PUT /auth/v1/admin/users/{id}` に `{"email":..., "email_confirm":true}` (service_role) で
     OTP を飛ばさず確認済にできる → `is_anonymous` が落ちるのを確認
   - `DELETE /auth/v1/admin/users/{id}` で掃除

## 落とし穴

- ❌ `role == 'authenticated'` で「本登録済」と判定する — 匿名も同じ値
- ❌ `updateUser({ email })` の成功を昇格完了と扱う — OTP 検証まで匿名のまま
- ❌ 昇格後に古いトークンを使い回す — claim が古く 403 が続く
- ❌ `email` の `null` チェックだけ書く — 匿名時は空文字列
- ⚠ 既定で無効。有効化を忘れると `signInAnonymously()` が
  `Anonymous sign-ins are disabled` で落ちる

## 関連

- [[gotcha/fake-store-tests-miss-db-constraint-drift]] — 「実物に当てるまで分からない」系の同型
