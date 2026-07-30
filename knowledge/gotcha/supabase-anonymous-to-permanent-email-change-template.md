---
title: Supabase 匿名 → 永続の昇格は 3 つ目のメールテンプレート (email_change) を通る
category: gotcha
project: global
tags: [supabase, gotoue, auth, anonymous, email-otp, email-change, template]
created: 2026-07-30
sources:
  - "一次確認 2026-07-30: GET https://api.supabase.com/v1/projects/{ref}/config/auth (omatase 本番) の mailer_* キーを実読"
  - https://raw.githubusercontent.com/supabase/auth/master/internal/api/verify.go
  - https://raw.githubusercontent.com/supabase/auth/master/internal/api/mail.go
  - Muraki/projects/omatase/CLAUDE.md (magic_link / confirmation の 2 テンプレートを code 化した記録)
---

## Context

匿名アカウント (`signInAnonymously`) で参加させ、後から `updateUser({ email })` +
`verifyOtp` で永続アカウントへ昇格させる設計。メールは「マジックリンクでなく 6 桁コード」で
送りたいので、Supabase のテンプレートを `{{ .Token }}` に書き換えて運用する。

## What

**メールテンプレートは 3 つある。昇格で飛ぶのは 3 つ目で、そこだけ既定のまま残りやすい。**

| フロー                                       | 飛ぶテンプレート                        | 件名キー                      |
| -------------------------------------------- | --------------------------------------- | ----------------------------- |
| 既存ユーザーのログイン (`signInWithOtp`)     | `mailer_templates_magic_link_content`   | `mailer_subjects_magic_link`  |
| 新規ユーザーの初回 (`shouldCreateUser:true`) | `mailer_templates_confirmation_content` | `mailer_subjects_confirmation`|
| **匿名 → 永続の昇格 (`updateUser({email})`)** | **`mailer_templates_email_change_content`** | **`mailer_subjects_email_change`** |

omatase では 1・2 を code 化した後も **3 が Supabase 既定の「Follow the link below…」のまま**で、
`{{ .Token }}` を含まなかった (2026-07-30 に Management API で実読)。
この状態で昇格画面を出すと**コードが届かずリンクだけ届く**ので、6 桁入力欄は永久に埋まらない。

**検証の `type` も別**: ログインは `verifyOtp({ type:"email" })` だが、
昇格は **`verifyOtp({ type:"email_change" })`**。

**`mailer_secure_email_change_enabled = true` (既定) でも、匿名ユーザーは二重確認にならない。**
GoTrue のソースで確認:

- `internal/api/mail.go`: `if config.Mailer.SecureEmailChangeEnabled && u.GetEmail() != ""` の
  ときだけ「現メール宛の OTP」も生成する。匿名ユーザーの email は **`''` (null ではない)** なので生成されない
- `internal/api/verify.go` の `emailChangeVerify`: 二重確認待ちに落とす条件が
  `... && user.GetEmail() != ""` なので、匿名ユーザーは**1 回の検証でセッションが返る**

→ このフラグを昇格のために false へ倒す必要はない。

## Why

GoTrue はフロー別にテンプレートを持ち、`updateUser({email})` は「メール変更」として扱われる。
匿名ユーザーは「メール未設定のユーザーのメール変更」であり、ログイン系のテンプレートを通らない。
1・2 を直した記憶があると「テンプレートは直してある」と思い込むが、**直っていないのは 3 つ目**。

## How to apply

- 昇格フローを設計/実装するなら、**`config/auth` を GET して 3 つのテンプレートを目で確認する**。
  「以前 code 化した」を根拠にしない
- 直すのは `mailer_templates_email_change_content` + `mailer_subjects_email_change` の 2 キー。
  `{{ .ConfirmationURL }}` は消す (リンクとコードの併記は混乱する)
- クライアント側の不変条件 (新セッションへの差し替え / `is_anonymous` が 2 段で落ちること) は
  [`library/supabase-anonymous-to-permanent-promotion`](../library/supabase-anonymous-to-permanent-promotion.md) に既にある。
  本ファイルはそこに**書かれていない 3 点** (テンプレートが 3 つ目 / `type:"email_change"` /
  secure_email_change は匿名では効かない) だけを持つ
- メールを読まずに確認したいときは admin `generate_link` を使うが、
  **`email_change_new` は現メールでユーザーを引くため匿名ユーザーには使えない**。
  ここは実機のメール受信で確認するしかない
