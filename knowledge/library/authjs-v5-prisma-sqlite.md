---
title: "Auth.js v5 + PrismaAdapter + SQLite (Magic Link + Google) 最小構成"
category: library
project: global
tags: [auth.js, next-auth, prisma, sqlite, magic-link, oauth]
created: 2026-05-08
sources:
  - https://authjs.dev/getting-started/adapters/prisma
  - https://authjs.dev/getting-started/providers/nodemailer
  - https://authjs.dev/guides/edge-compatibility
  - https://authjs.dev/reference/core#session
  - https://github.com/nextauthjs/next-auth/releases
---

## Context
Next.js 15 App Router + Prisma + better-sqlite3 で Auth.js v5 を使い、
Magic Link (Email) + Google OAuth を実装する場合の最小構成。

## What
- **v5 はまだ stable 未リリース** (2026-05 時点で next-auth@5 はベータ表記、
  releases 公開済み stable は依然 4.24.14 系)。Researcher が確認したのは v5-beta の挙動。
- Magic Link (旧 EmailProvider) は **`Nodemailer`** プロバイダーに改名。
  Next.js では `next-auth/providers/nodemailer`、コアでは `@auth/core/providers/nodemailer`。
- **データベース必須**: Magic Link は VerificationToken を保存するため
  必ず DB アダプター (PrismaAdapter 等) が要る。JWT-only では動かない。
- **session.strategy**:
  - `"database"` がアダプター利用時のデフォルトで普通に使える
  - `"jwt"` は **Edge/Middleware で DB を呼べない場合の回避策**として推奨されるだけ
  - middleware で重い認可をしないなら `"database"` のままで問題ない
- **split-config パターン**: edge-safe な `auth.config.ts` (providers のみ) と
  Node-only な `auth.ts` (PrismaAdapter を足す) に分割して `middleware.ts` から前者だけ参照する。

## Why
- v5 の最大の罠は「Edge runtime と Prisma は同居不可」。
  middleware にアダプターを直接刺すと build できる場合でも実行時に死ぬ。
- 旧 EmailProvider のコード/ドキュメントを参照すると import path で詰まる。

## How to apply
1. Prisma schema は User / Account / Session / VerificationToken の 4 モデルを必ず定義
   (Authenticator は WebAuthn を使う場合のみ追加)。
2. `auth.config.ts` に Google + Nodemailer providers を書き、middleware から import。
3. `auth.ts` で `NextAuth({ adapter: PrismaAdapter(prisma), ...authConfig })` をエクスポート。
4. MVP の Magic Link 送信は dev で `sendVerificationRequest` 内で `console.log(url)` し、
   prod で初めて Resend / SMTP に切り替えると最小摩擦。
5. `npm install next-auth@beta @auth/prisma-adapter` を明示すること
   (`next-auth` だけだと v4 stable が入る)。
