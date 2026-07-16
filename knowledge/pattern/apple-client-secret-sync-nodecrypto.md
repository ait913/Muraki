---
title: Apple Sign in の client secret を node:crypto で同期生成し auth 初期化の async 化を避ける
category: pattern
project: global
tags: [auth, apple-signin, better-auth, jwt, es256, node-crypto, ios]
created: 2026-07-14
sources:
  - Atender .designs/20260714-ios-login-auth-revamp.md
  - https://www.better-auth.com/docs/authentication/apple
---

## Context

better-auth (や NextAuth) の Apple provider は `clientSecret` を必須にするが、Apple の client secret は **ES256 で署名した JWT** で最長6ヶ月失効する。静的に手貼りすると失効時に無言で死ぬ運用地雷。動的生成したいが、`jose` の `SignJWT` は **async** で、`getAuth()` が同期 Proxy から全 route に呼ばれる構成だと auth 初期化全体を async 化する破壊的リファクタになる。

## What

- **client secret JWT を `node:crypto` で同期生成する**。jose 不要・async 化不要。
- 鍵は Apple の Sign in with Apple Key (.p8, P-256)。ES256 の JWT 署名は raw `r||s` (P1363) 形式が必須で、`crypto.sign` の `dsaEncoding: "ieee-p1363"` がそれを出す (既定の DER だと JWT 検証が通らない)。
- ペイロード: `iss=TeamID`, `sub=ServiceID(=clientId)`, `aud="https://appleid.apple.com"`, `iat`, `exp=iat+180日`。ヘッダ: `{alg:"ES256", kid:KeyID, typ:"JWT"}`。
- provider config を成立させる目的なので、iOS ネイティブ idToken 経路 (`POST /sign-in/social {provider:"apple", idToken}`) では client secret は暗号的に未使用でも「provider を有効化するために」正しい secret を持たせる方が壊れにくい (dummy 依存にしない)。native の audience は `appBundleIdentifier` (= アプリの bundle id)、`clientId` は Service ID。

```ts
import { createPrivateKey, sign as cryptoSign } from "node:crypto";
const b64url = (b: Buffer) => b.toString("base64url");
const header = b64url(Buffer.from(JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" })));
const payload = b64url(Buffer.from(JSON.stringify({ iss: teamId, iat, exp, aud: "https://appleid.apple.com", sub: clientId })));
const signingInput = `${header}.${payload}`;
const sig = cryptoSign("sha256", Buffer.from(signingInput), { key: createPrivateKey(pem), dsaEncoding: "ieee-p1363" });
const jwt = `${signingInput}.${b64url(sig)}`;
```

## Why

- `getAuth()` が同期のままなら bearer/session middleware も既存のまま。async 化は影響範囲が全 route に広がりリスク>便益。
- 静的 client secret は6ヶ月失効の footgun。boot 時生成で失効管理が消える (プロセス再起動ごとに新 JWT)。静的は env `APPLE_CLIENT_SECRET` を脱出口として残す (`?? 動的生成`)。
- `dsaEncoding: "ieee-p1363"` を忘れると DER 署名になり Apple/検証側で必ず落ちる — ここが唯一の非自明ポイント。

## How to apply

1. env に `APPLE_TEAM_ID` / `APPLE_KEY_ID` / `APPLE_PRIVATE_KEY`(.p8 PEM, 改行は `\n` エスケープ→loader で復元) を追加。`APPLE_CLIENT_ID`=Service ID, `APPLE_APP_BUNDLE_ID`=bundle id。
2. `buildAppleClientSecret({teamId,keyId,privateKeyPem,clientId}, now?)` を純関数 (now 注入で決定的) にして単体テスト: 3セグJWT / header alg=ES256,kid / payload iss,sub,aud,exp=iat+180日 / signature デコード 64byte (P-256 raw)。
3. `getAppleProviderConfig()` は `clientSecret = APPLE_CLIENT_SECRET ?? (3点揃えば buildAppleClientSecret(...))`、無ければ provider を null で外す。
4. Apple JWKS を使う実 idToken 検証は外部依存なので E2E/実機送り、Vitest は生成の構造検証のみ。
