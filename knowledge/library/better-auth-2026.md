---
title: better-auth 1.6.x (2026-05) — Next.js + Prisma + Magic Link + OAuth 最小構成
category: library
project: global
tags: [auth, better-auth, next-auth-alternative, magic-link, prisma, sqlite, oauth]
created: 2026-05-13
sources:
  - https://www.better-auth.com/docs/introduction
  - https://www.better-auth.com/docs/plugins/magic-link
  - https://www.better-auth.com/docs/integrations/next
  - https://www.better-auth.com/docs/adapter/prisma
  - https://www.better-auth.com/docs/integrations/hono
  - npm view better-auth (2026-05-13)
---

## Context

Next.js (App Router) + Prisma + SQLite で「Magic Link + Google OAuth + DB session」を最小コストで組みたい場面。Auth.js v5 が長らく beta のままなので 2026 年の現実解として better-auth が浮上。

## What

- **バージョン**: 2026-05-12 publish の `1.6.11` が `latest` (stable)。`beta` tag は `1.7.0-beta.3` (`npm view better-auth dist-tags`)。Auth.js v5 がまだ `5.0.0-beta.31` なのに対し、**better-auth の方が stable** という逆転状況
- **特徴**:
  - Plugin 形式 (magicLink, twoFactor, organization, passkey 等を後付け可)
  - Prisma / Drizzle / Kysely adapter 公式提供、SQLite/Postgres/MySQL 対応
  - DB session (HTTP-only cookie + DB row) がデフォルト。JWT セッションも可能だが推奨しない
  - 自動推論される型 — `auth.api.getSession()` の戻り型は plugin 構成から導出される
- **Next.js 統合** ([docs](https://www.better-auth.com/docs/integrations/next)):
  - Handler は `app/api/auth/[...all]/route.ts` に `export const { GET, POST } = toNextJsHandler(auth)`
  - Server Component から `auth.api.getSession({ headers: await headers() })` を都度呼ぶ流儀 (middleware/proxy 依存しない)
  - Server Action 内で cookie を set する場合は `nextCookies()` プラグインを足す
- **Hono 統合** ([docs](https://www.better-auth.com/docs/integrations/hono)):
  - `app.on(["POST", "GET"], "/api/auth/**", (c) => auth.handler(c.req.raw))`
  - クロスオリジン (Capacitor 等) は `trustedOrigins` 配列に追加
- **Magic Link プラグイン**:
  - `magicLink({ expiresIn?, sendMagicLink: async ({ email, token, url, request? }) => void })`
  - デフォルト `expiresIn=300s` は短い、`60*15` 程度に伸ばすのが実用的
  - メール送信は SDK 自由 (Resend / Nodemailer / Postmark / SendGrid 等)
- **Google OAuth**:
  - `socialProviders.google: { clientId, clientSecret }` だけ
  - リダイレクト URL は `<BETTER_AUTH_URL>/api/auth/callback/google`
- **Prisma スキーマ**: `npx @better-auth/cli generate` で User / Session / Account / Verification の 4 テーブルが自動生成。Atender 等の独自モデルとは別ファイルに分けて `model User { ... attendances Attendance[] }` のように relation を後付け

## Why

- Auth.js v5 が 2024 から beta のまま停滞している隙に、Plugin 形式 + 強い型推論 + DB-first 設計で支持を集めた
- session ベース DB 管理が標準なので **後で Capacitor 化 (cross-origin) する時に JWT に切り替える必要がない** — cookie の `SameSite=None; Secure` 設定だけで済む
- Lucia deprecate ([[library/lucia-deprecated-2025]]) の受け皿として急速に普及

## How to apply

### 最小実装 (Next.js + Prisma + SQLite + Resend Magic Link)

```ts
// lib/auth.ts
import { betterAuth } from "better-auth"
import { prismaAdapter } from "better-auth/adapters/prisma"
import { magicLink } from "better-auth/plugins"
import { nextCookies } from "better-auth/next-js"
import { Resend } from "resend"
import { prisma } from "./db"

const resend = new Resend(process.env.RESEND_API_KEY)

export const auth = betterAuth({
  database: prismaAdapter(prisma, { provider: "sqlite" }),
  socialProviders: {
    google: {
      clientId: process.env.GOOGLE_CLIENT_ID!,
      clientSecret: process.env.GOOGLE_CLIENT_SECRET!,
    },
  },
  plugins: [
    magicLink({
      expiresIn: 60 * 15,
      sendMagicLink: async ({ email, url }) => {
        await resend.emails.send({
          from: "App <noreply@example.com>",
          to: email,
          subject: "ログイン用リンク",
          html: `<a href="${url}">サインインする</a>`,
        })
      },
    }),
    nextCookies(),
  ],
})
```

```ts
// app/api/auth/[...all]/route.ts
import { toNextJsHandler } from "better-auth/next-js"
import { auth } from "@/lib/auth"
export const { GET, POST } = toNextJsHandler(auth)
```

### Prisma スキーマ生成

```sh
npx prisma init --datasource-provider sqlite
npx @better-auth/cli@latest generate --output prisma/schema.prisma
npx prisma migrate dev --name init
```

### 採用判断のチェックリスト

- ✅ Next.js / Hono / Express など Node ベース → 採用 OK
- ✅ session-based を維持したい → 採用 OK
- ✅ Capacitor / RN への移行予定あり → 採用 OK (cookie 設定変更だけで済む)
- ❌ Edge runtime のみで動かしたい (Cloudflare Workers の D1 等) → adapter 制約を確認、場合により Lucia 後継の自前実装の方が軽い

### 落とし穴 (Atender 着手前の予防メモ)

- `nextCookies()` プラグインを忘れると Server Action 経由のサインインで cookie が落ちる
- `BETTER_AUTH_URL` env 必須。Coolify では prod URL を直書きする
- Capacitor / クロスオリジン環境では `trustedOrigins: ["capacitor://localhost"]` を **足し忘れない**
- Magic Link 送信先のドメインは Resend で `verify` 済みでなければ送れない (SPF/DKIM TXT 必須)

## 関連

- [[library/lucia-deprecated-2025]] — Lucia は採用しない
- [[library/authjs-v5-prisma-sqlite]] — 旧推奨案 (今後は better-auth 推奨)
