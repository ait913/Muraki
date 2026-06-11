---
title: better-auth incremental scope (linkSocial) + cron 文脈での access token 取得パターン
category: pattern
project: global
tags: [better-auth, oauth, google, incremental-authorization, refresh-token, cron, background-job, prisma]
created: 2026-05-28
sources:
  - https://www.better-auth.com/docs/concepts/oauth
  - https://www.better-auth.com/docs/authentication/social-providers
  - https://developers.google.com/identity/protocols/oauth2/web-server#incremental-auth
  - https://developers.google.com/identity/protocols/oauth2/web-server#offline
  - projects/atender/.designs/20260528-v8-google-calendar-oauth.md
related_knowledge:
  - knowledge/library/better-auth-2026.md
  - projects/atender/.knowledge/07-google-calendar-oauth-integration.md
---

## Context

既に better-auth で Google Sign-In を持つアプリで、後から「Google Calendar 読み取り」など追加 scope が必要になる場面。sign-in 時に sensitive scope を最初から要求すると consent screen がうるさく離脱率が上がるので、機能利用の文脈で scope を段階要求したい (= incremental authorization)。

加えて、取得した refresh_token を **cron / background job** (= session cookie が無い文脈) から使って API を叩く需要がある (例: 1 時間ごとの定期同期)。

## What

### 1. sign-in と Calendar scope を分離

```ts
// auth.ts
socialProviders: {
  google: {
    clientId, clientSecret,
    // scope は base のまま (openid email profile) — Calendar は要求しない
    accessType: "offline",   // refresh_token を確実に発行
    prompt: "consent",       // 既存ユーザーの再認可時にも refresh_token を再発行
  },
},
```

### 2. linkSocial で追加 scope を後付け取得

```ts
// web 側
await authClient.linkSocial({
  provider: "google",
  scopes: ["https://www.googleapis.com/auth/calendar.readonly"],
  callbackURL: "/settings/integrations/google?linked=1",
});
```

- better-auth 1.2.7+ で「既に連携済みの同一プロバイダ」に対しても scope を追加可能
- better-auth が `include_granted_scopes=true` を OAuth URL に default で付与する (要確認、v1.6.x 仕様)
- 完了後 Account.scope が space-separated で更新される

### 3. token 自動 refresh 経路 (2 パス)

#### API ハンドラ文脈 (session cookie あり)

```ts
const { accessToken } = await auth.api.getAccessToken({
  body: { providerId: "google" },
  headers: c.req.raw.headers,
});
```

#### cron / background job 文脈 (session cookie なし)

```ts
// primary path
const { accessToken } = await auth.api.getAccessToken({
  body: { providerId: "google", userId },   // userId 直渡し
});
```

★ ただし **better-auth 1.6.11 で userId 直渡しが本当に動くかは未確定**。動かない場合は fallback:

```ts
async function refreshGoogleTokenManually(userId: string): Promise<string> {
  const account = await prisma.account.findFirst({
    where: { userId, providerId: "google" },
  });
  if (!account?.refreshToken) throw new Error("no refresh_token");

  const body = new URLSearchParams({
    client_id: env.GOOGLE_CLIENT_ID,
    client_secret: env.GOOGLE_CLIENT_SECRET,
    refresh_token: account.refreshToken,
    grant_type: "refresh_token",
  });
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  const data = await res.json();
  await prisma.account.update({
    where: { id: account.id },
    data: {
      accessToken: data.access_token,
      accessTokenExpiresAt: new Date(Date.now() + data.expires_in * 1000),
    },
  });
  return data.access_token;
}
```

### 4. REVOKED 判定の標準化

`auth.api.getAccessToken` が `APIError { code: "FAILED_TO_GET_ACCESS_TOKEN" | "INVALID_GRANT" }` を throw したら、ユーザーが Google 側で連携解除した signal。自前モデル (例: GoogleCalendarConnection) を `status=REVOKED` に更新し、UI で「再連携してね」を出す。

## Why

- sign-in と機能利用の consent を**時間軸で分ける**ことで離脱率と UX を改善できる (= Calendly / Reclaim 等の SaaS 標準)
- cron 文脈での token 取得が型・経路として primary / fallback の 2 段で揃うと、better-auth の future 仕様変更にも耐えられる
- REVOKED 判定を Connection 行で持つと、UI 側で「使えない sync」と「ただ繋いでない sync」を区別表示できる

## How to apply

- 既存 better-auth プロジェクトに後付け OAuth scope を入れる時、scope を auth.ts に書かず linkSocial で取得する
- cron 文脈で token が必要なら primary + fallback を両方実装し、最初の cron 実行ログで「どちら経路が走ったか」を console.log で確認
- `Account.scope` をパースして UI に「許可済の権限」を表示するなら space-separated string を `.split(" ")` で扱う
- prompt: "consent" は **再認可で refresh_token が再発行される** ために必要 (default は再発行されない)
- include_granted_scopes が default かどうかは better-auth source / 実環境の OAuth URL を 1 度確認すべし

## 関連

- [[library/better-auth-2026]] — better-auth 1.6.x の基本構成
- [[gotcha/better-auth-test-cookie-must-match-hono-signed-format]] — テスト時の cookie 形式 (関連)
