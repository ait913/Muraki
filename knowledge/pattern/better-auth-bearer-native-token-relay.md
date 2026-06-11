---
title: better-auth Cookie session を壊さず bearer plugin でネイティブを併存させる + Google web OAuth の token 中継
category: pattern
tags: [auth, better-auth, ios, swiftui, bearer, oauth, apple-signin, keychain, native]
created: 2026-06-08
project: global
sources:
  - https://www.better-auth.com/docs/plugins/bearer
  - Atender .designs/20260608-ios-foundation.md
  - apps/api/src/auth.ts / middleware/session.ts (atender)
---

## Context

既に web で **better-auth の Cookie session** (`credentials:"include"`, SameSite=Lax, DB session) を運用しているプロダクトに、後から **iOS ネイティブ (SwiftUI)** や Capacitor/RN クライアントを足す場面。ネイティブは Cookie を使えない (URLSession / WKWebView の cookie 共有が不安定) ので token ベースが要る。Atender iOS 土台設計で確定した。

## What

- **Cookie を JWT に切り替える必要はない**。better-auth `bearer()` plugin を `plugins` に足すだけで、既存 DB session token を `Authorization: Bearer <token>` で受けられるようになる。web (Cookie) とネイティブ (Bearer) が**同一 session 基盤で併存**する。
- bearer はサインインレスポンスの `set-auth-token` ヘッダに token を載せる。`auth.api.getSession({ headers })` が Bearer ヘッダを解決するので、`getSession` を先に呼ぶ既存 session middleware は**多くの場合変更不要**(バージョン挙動は要検証、見ない場合のみ middleware に Bearer→token 抽出を追加)。
- **Apple Sign-In はネイティブ idToken 直渡し**が綺麗: `POST /api/auth/sign-in/social` body `{provider:"apple", idToken:{token}}`。API 側は apple social provider に `appBundleIdentifier` を設定し、ネイティブ idToken の audience を許可する。
- **Google web OAuth は token 受け渡しが厄介**: `ASWebAuthenticationSession` は ephemeral でない限り Cookie をアプリと共有せず、redirect なので `set-auth-token` ヘッダもアプリから読めない。→ **API に薄い中継ハンドラ**を新設し、session 確立後に session token を **custom scheme の URL fragment** (`atender://auth#token=<sessionToken>`) に載せて redirect する。ネイティブは fragment から token 抽出 → Keychain 保存。これで Google も Apple と同じ最終処理に揃い、Google ネイティブ SDK が不要になる。
- 中継ハンドラはオープンリダイレクト防止のため `next` を `trustedOrigins` で検証。custom scheme (`atender://auth`) は `trustedOrigins` に追加が必要。
- token は **Keychain** に `kSecClassGenericPassword` + `kSecAttrAccessibleAfterFirstUnlock` で保存 (将来の background fetch 許容)。401 受信で破棄 → signedOut。30 日 expiry なら silent refresh は当面不要。

## Why

- DB session を維持すると失効をサーバ側で制御でき、web を一切壊さずネイティブを足せる。JWT 化は失効制御を失い移行リスクが高い。
- Apple は idToken をネイティブで直接取れる (AuthenticationServices) ので中継不要。Google は OAuth web flow を SDK なしでやると Cookie/header がアプリに届かないため、サーバ中継で fragment 渡しが最小コストの確実解。
- bearer plugin は既存 Cookie 認証と非破壊で共存するのが最大の利点。

## How to apply

1. `auth.ts` の `plugins` に `bearer()` を追加 (magicLink 等と併存)。
2. `socialProviders.apple` に `clientId / clientSecret / appBundleIdentifier` を追加。env 追加分は test env に dummy を入れて既存テストを壊さない。
3. `trustedOrigins` (env CSV) に custom scheme (`atender://auth`) を追加。
4. Google 用に `GET /api/auth/native/callback?next=<scheme>` 中継を新設。session 確立済みなら `<scheme>#token=<sessionToken>` へ 302、未認証 401、next が trustedOrigins 外 400。
5. ネイティブ: Apple=idToken 直渡し、Google=ASWebAuthenticationSession + 中継 fragment 抽出。両者とも最終的に token を Keychain へ。
6. テスト: Vitest で「Bearer ヘッダで /api/me 200 / 不正 token 401」「中継ハンドラの Location が `scheme#token=` 形式 / token が DB session 一致 / 未認証 401 / 不正 next 400」。Apple idToken 検証は外部公開鍵依存なので E2E (実機/TestFlight) 送り、Vitest は構成テストのみ。

## 関連

- [[library/better-auth-2026]] — better-auth 基本構成
- [[pattern/better-auth-incremental-scope-and-cron-token]] — Google 追加 scope (ネイティブでの linkSocial は Phase 後送り)
