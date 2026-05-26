---
title: better-auth 1.6.x + Hono + Drizzle + SQLite 構成 (Anonymous Plugin 含む 2026-05)
category: library
project: global
tags: [auth, better-auth, hono, drizzle, sqlite, anonymous, session, cookie, guest-user]
created: 2026-05-26
sources:
  - https://www.better-auth.com/docs/integrations/hono
  - https://www.better-auth.com/docs/adapters/drizzle
  - https://www.better-auth.com/docs/plugins/anonymous
  - https://www.better-auth.com/docs/concepts/session-management
  - https://github.com/better-auth/better-auth/blob/main/packages/better-auth/src/plugins/anonymous/index.ts
  - https://github.com/better-auth/better-auth/blob/main/packages/better-auth/src/plugins/anonymous/types.ts
  - https://github.com/better-auth/better-auth/blob/main/packages/better-auth/src/db/internal-adapter.ts
  - https://github.com/LovelessCodes/hono-better-auth
---

## Context

Web アプリで「Hono + Drizzle + SQLite + better-auth」スタックを採用する場面、特に Anonymous Plugin で「名前のみのゲスト運用」をする場合。既存 [`library/better-auth-2026.md`](better-auth-2026.md) は Next.js + Prisma 前提なので、本書は Hono + Drizzle 差分 + anonymous 詳細を集約。

## What

### 依存 (2026-05-26 npm 最新)

```json
{
  "dependencies": {
    "better-auth": "^1.6.11",
    "@better-auth/cli": "^1.4.21",
    "@better-auth/drizzle-adapter": "^1.6.11",
    "drizzle-orm": "^0.45.2",
    "better-sqlite3": "^12.10.0",
    "hono": "^4.12.23",
    "@hono/node-server": "^2.0.4",
    "zod": "^4"
  },
  "devDependencies": {
    "drizzle-kit": "^0.31.10",
    "@types/better-sqlite3": "^7"
  }
}
```

### Anonymous Plugin の API 仕様 (verbatim from source)

```ts
// AnonymousOptions
export interface AnonymousOptions {
  emailDomainName?: string;
  generateRandomEmail?: () => string | Promise<string>;
  onLinkAccount?: (data: {
    anonymousUser: { user: UserWithAnonymous; session: Session };
    newUser: { user: User; session: Session };
    ctx: GenericEndpointContext;
  }) => Awaitable<void>;
  disableDeleteAnonymousUser?: boolean;
  generateName?: (
    ctx: EndpointContext<"/sign-in/anonymous", { method: "POST" }, AuthContext>
  ) => Awaitable<string>;
  schema?: InferOptionSchema<typeof schema>;
}
```

**重要事実**:
- `POST /api/auth/sign-in/anonymous` は **body schema 無し** (ctx.body 未参照)。**クライアントから名前を渡す公式 API は存在しない**
- `generateName(ctx)` は request コンテキストを受け取るので、**カスタムヘッダから name を読み取れる** (★ Touri 検証推奨パターン)
- User 表に `isAnonymous` (boolean) フィールドが必須追加される
- `email` は必須 + unique のままなので、anonymous user 用に `generateRandomEmail()` で `<uuid>@anon.local` 等を自動生成 (default 動作あり)

### 最小 auth.ts

```ts
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "@better-auth/drizzle-adapter";
import { anonymous } from "better-auth/plugins";
import { db } from "./db";
import * as authSchema from "./db/auth-schema";

export const auth = betterAuth({
  baseURL: process.env.BETTER_AUTH_URL!,
  secret: process.env.BETTER_AUTH_SECRET!,
  database: drizzleAdapter(db, { provider: "sqlite", schema: authSchema }),
  session: {
    expiresIn: 60 * 60 * 24 * 30, // 30 days
    updateAge:  60 * 60 * 24,
  },
  plugins: [
    anonymous({
      generateName: (ctx) => ctx.request?.headers.get("x-guest-name") ?? "ゲスト",
    }),
  ],
  trustedOrigins: [process.env.BETTER_AUTH_URL!],
});
```

### Drizzle schema (anonymous フィールド追加版)

```ts
import { index, integer, sqliteTable, text } from "drizzle-orm/sqlite-core";

export const user = sqliteTable("user", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  email: text("email").notNull().unique(),
  emailVerified: integer("email_verified", { mode: "boolean" }).default(false).notNull(),
  image: text("image"),
  isAnonymous: integer("is_anonymous", { mode: "boolean" }).default(false).notNull(),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
  updatedAt: integer("updated_at", { mode: "timestamp_ms" }).$onUpdate(() => new Date()).notNull(),
});
// session / account / verification は LovelessCodes/hono-better-auth から流用
```

**手書きより推奨**: `npx @better-auth/cli generate` で plugin 込みの schema を自動生成。

### Hono mount

```ts
import { Hono } from "hono";
import { cors } from "hono/cors";
import { auth } from "./auth";

const app = new Hono<{
  Variables: {
    user: typeof auth.$Infer.Session.user | null;
    session: typeof auth.$Infer.Session.session | null;
  };
}>();

app.use("/api/*", cors({ origin: ..., credentials: true }));

app.use("/api/*", async (c, next) => {
  const session = await auth.api.getSession({ headers: c.req.raw.headers });
  c.set("user", session?.user ?? null);
  c.set("session", session?.session ?? null);
  await next();
});

app.on(["POST", "GET"], "/api/auth/**", (c) => auth.handler(c.req.raw));
```

### Session / Cookie 設定

- デフォルト: `session.expiresIn = 60*60*24*7` (7日), `updateAge = 60*60*24` (1日)
- 30日 cookie 保持要件は `expiresIn: 60*60*24*30` で達成
- cookie maxAge は session expiresAt に追随 (`updateAge` 経過時に session 行と cookie の両方更新)
- cookie 名: `better-auth.session_token` (HMAC-signed via `BETTER_AUTH_SECRET`)
- HTTPOnly + secure (prod) + SameSite (default lax) は自動

## Why

- Next.js + Prisma 版とは **adapter / handler mount / cookie plugin / session 取得方法** が違う。Hono 流儀を明示しておかないと Architect が Next.js 流儀で設計 doc を書く事故が起きる
- Anonymous Plugin の body 不在仕様は docs に明記なし。source code を引かないと「クライアントから name を渡せない」事実に気付けない
- `generateName` の ctx 引数仕様は docs に書いてない (Touri チームでは source 確認済)

## How to apply

### 名前のみゲスト運用 (3 案)

| 案 | 操作 | サーバ |
|---|---|---|
| **A** | `signIn.anonymous()` → `auth.api.updateUser({ name })` の 2 リクエスト | デフォルト |
| **B** | 独自 `POST /api/guest { name }` の 1 リクエスト | Hono に独自 route + 内部で signInAnonymous + updateUser |
| **C** ★推奨 | `signIn.anonymous({ fetchOptions: { headers: { "x-guest-name": name } } })` の 1 リクエスト | `generateName: ctx => ctx.request.headers.get("x-guest-name") ?? ...` |

### app export 規約 ([関連 gotcha](../gotcha/design-must-specify-app-export-path-for-tests.md))

- `src/app.ts` から `export const app` (named)
- `src/index.ts` は薄い `serve({ fetch: app.fetch })` wrapper
- テストは `import { app } from "../../src/app"` → `app.request(...)` で叩く

### CORS 必須項目

- `credentials: true` (cookie 含むため)
- `trustedOrigins` も同時設定 (better-auth 側の CSRF 防御)

### Migration

- `npx @better-auth/cli generate` で schema 生成 (auth.ts の plugin 構成から導出)
- `bunx drizzle-kit generate` → `drizzle-kit migrate` で適用

## 落とし穴

- ✅ [Hono signed cookie 形式](../gotcha/better-auth-test-cookie-must-match-hono-signed-format.md): テスト時 cookie 偽造で必ずハマる
- ✅ [app export path 不明示](../gotcha/design-must-specify-app-export-path-for-tests.md): 設計 doc で必ず指定
- email が必須 + unique なので、anonymous user で `generateRandomEmail` を上書きしない場合 builtin 動作に依存
- `auth.api.signInAnonymous` を server から呼ぶ場合、`{ headers, asResponse: true }` の組み合わせで cookie を取り出せるかは未検証
- `kysely@0.28` を better-auth が依存に持つ → 別途 kysely を入れない (バージョン衝突)
- zod v4 を better-auth が要求 → `@hono/zod-validator@0.8+` (zod v4 系) を使うこと

## 関連

- [[library/better-auth-2026]] — Next.js + Prisma 版
- [[library/lucia-deprecated-2025]] — Lucia は採用しない
- [[gotcha/better-auth-test-cookie-must-match-hono-signed-format]]
- [[gotcha/design-must-specify-app-export-path-for-tests]]
