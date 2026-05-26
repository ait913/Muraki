---
title: better-auth テスト helper の cookie は Hono signed cookie 形式を再現する必要がある
category: gotcha
tags: [better-auth, hono, vitest, testing, cookie, hmac]
created: 2026-05-13
project: global
sources:
  - node_modules/better-auth/dist/cookies/index.mjs (1.6.x)
  - node_modules/hono/dist/utils/cookie.js (4.12.x)
---

## Context

better-auth 1.6.x + Hono 4.12.x の API を Vitest + `app.request()` でテストする際、テスト helper で「Session 行を直接 prisma で作って Cookie ヘッダで認証通過させる」パターンを取りがち。素朴な実装 `better-auth.session_token=${rawToken}` は全テストが 401 で落ちる。

## What

better-auth は cookie 発行を **Hono の `setSignedCookie(name, value, secret, attrs)` 経由** で行い、検証側も `getSignedCookie(c, secret, name)` で取り出す。Hono signed cookie の形式は厳密に決まっている:

- cookie 値 = `${rawValue}.${signature}`
- `signature = base64(HMAC-SHA256(secret, rawValue))` (base64 標準、44 文字、末尾 `=`)
- パース時に `signature.length !== 44 || !signature.endsWith("=")` を満たさないと拒否

つまり raw token を平文で入れた cookie は形式不正で **signature が剥がれず token も取り出されず 401**。

Node 側で生成するなら:
```ts
import { createHmac } from "node:crypto";
const signature = createHmac("sha256", process.env.BETTER_AUTH_SECRET!)
  .update(token).digest("base64"); // 44 文字 標準 base64
const cookie = `better-auth.session_token=${token}.${signature}`;
```

加えて better-auth は `baseURL` のプロトコルや `isProduction` で cookie name に `__Secure-` prefix を付ける。テスト env で `BETTER_AUTH_URL=http://...` を渡しているなら無しでよいが、念のため両 name を `; ` 連結で同時に送ると安全。

## Why

better-auth 公式 docs は `Session` テーブルへの直挿しでの cookie 偽造方法を案内していないため、Hono signed cookie の内部仕様を **third-party のソース** (`node_modules/hono/dist/utils/cookie.js` の `makeSignature` / `parseSigned`) と **better-auth の `dist/cookies/index.mjs` の `setSessionCookie`** を読まないと再現できない。設計 doc に「テスト時の cookie 発行方法」を書いておかないと Reviewer が必ず一度ハマる。

Cookie value regex `/^[ !#-:<-[\]-~]*$/` には base64 標準の `+/=` が含まれるので URL encode は不要 (むしろ encode すると一致しなくなる)。

## How to apply

- 設計 doc の「テスト基盤」節に **「テスト session cookie は Hono signed cookie 形式 (`${token}.${hmac_base64}`) で生成する」** を明記する
- helper は **第三者ライブラリのソース** (better-auth / Hono) を読んで仕様確認するのは OK、ただし**アプリ実装 (`src/`) は見ない**でテストを書くという Reviewer 規律は守る
- helper 単体での署名一致は Node REPL で `crypto.subtle.verify` 経由 self-check を一回しておくと、その後の 401 切り分けが「実装側 = better-auth handler 未マウント / secret 未一致 / Session row schema 違い」のどれかに絞り込める
- 401 が helper 修正でも消えない場合、`POST /api/auth/sign-in/magic-link` の status を probe して **better-auth handler が `app.on(["POST","GET"], "/api/auth/*", c => auth.handler(c.req.raw))` で mount されているか**を切り分ける。404 が返るならそれは実装側の不備
