---
title: Capacitor 8 + Next.js 16 で iOS ハイブリッドアプリを組む (2026年5月時点)
category: library
tags: [capacitor, nextjs, ios, mobile, webview]
created: 2026-05-11
project: global
sources:
  - https://capacitorjs.com/
  - https://github.com/ionic-team/capacitor/releases
  - https://nextjs.org/
  - https://nextnative.dev/
  - https://capawesome.io/
---

## Context
個人開発で「iPhone がメイン、Web も触れる」ハイブリッドアプリを最小コストで作る場面。Expo (React Native) との二択で Capacitor を選んだ時。

## What
**Capacitor 現状 (2026/5)**:
- v8 stable (2025/12 リリース)、v9 alpha (2026/5/7 公開)
- iOS の依存解決は **SPM (Swift Package Manager) がデフォルト** に (CocoaPods から移行)
- 開発要件: Node.js 22+、macOS Sonoma 14+ (Tahoe 26 推奨)、Xcode 26+、Apple Developer Program ($99/年)
- 2026/4/28 以降、App Store 提出は **iOS 26 SDK** ビルド必須
- `bundledWebRuntime` 廃止 → `@capacitor/core` バンドル必須

**Next.js 現状 (2026/5)**:
- v16 系が主流。App Router + RSC + Turbopack がデフォルト
- Pages Router はレガシー保守
- `middleware.ts` は `proxy.ts` に rename される動きあり (要確認)

**Capacitor + Next.js 統合パターン**:
- **(a) 推奨: `output: 'export'` で静的書き出し → iOS バンドルに同梱**
  - 起動速い、オフライン動作、App Store Guideline 4.2 通過率高
  - Server Actions / Route Handlers (POST等) / middleware / ISR / next/image 最適化 / next/headers 全て使えない
- (b) `server.url` をリモート Next.js に向ける → 全機能使えるがオフライン死、Apple に「Web ラップ」と判定されるリスク
- (c) ハイブリッド: 静的シェル + 外部 API 叩く ← **2026 の事実上標準**

**App Router static export の落とし穴**:
- 動的ルート (`[id]`) は `generateStaticParams` で全列挙必須。多すぎるならクエリパラメータ (`?id=`) 設計に切り替え
- `trailingSlash: true` 必須 (WebView ディレクトリ解釈)
- `assetPrefix` / `basePath` 設定漏れで `capacitor://localhost` から白画面

**WebView UX 制約 (iOS 17-19)**:
- `viewport-fit=cover` 必須 (Dynamic Island / Liquid Glass 対応)
- キーボード: `Keyboard.setResizeMode({ mode: 'none' })` + CSS 変数手動パディングが定石
- スクロールバウンス: `overscroll-behavior: none` だけでは効かず、ネイティブ側で `webView.scrollView.bounces = false` 設定が必要なケースあり

**UI ライブラリ選定 (2026)**:
- **Konsta UI** (Tailwind ベース、Liquid Glass 美学再現): iOS look-and-feel 最優先ならこれ
- **Tamagui**: コンパイラ最適化で 60fps、Web/Native 両対応
- **Ionic Framework**: 堅牢だが Shadow DOM でカスタム難
- 定番組合せ: **Tailwind + Konsta UI + @capacitor/haptics**

**通知プラグイン**:
- `@capacitor/push-notifications`: APNs token (Hex) を返す
- `@capacitor/local-notifications`: 共存 OK、`InterruptionLevel`(Time Sensitive 等) 指定可
- FCM 経由なら `@capacitor-firebase/messaging` (Capawesome 製) が 2026 標準

## Why
- Expo は RN ネイティブで Capacitor は WebView。Web 知識資産 (Next.js) を流用したいなら Capacitor の方が学習コスト低い
- Next.js を選ぶ場合、static export の制約を **設計段階で受け入れる** ことが必須。Server Actions 前提で設計してから「使えない」と気付くと作り直しになる
- iOS 26 SDK 必須化が 2026/4 で確定したので、Xcode 26 と macOS 14+ は実機が必要

## How to apply
- tomori のような個人秘書アプリは「Capacitor + Next.js (output: export) + Hono 等別バックエンド」が現実的
- バックエンド処理は全て fetch (絶対 URL) で呼ぶ前提で API 層を設計
- Web 公開も同じ Next.js (export 版) を別ホストで配信できるので 1 コードベースで両対応可能
- 動的ルートは最小化、クエリパラメータ設計を優先
- 認証は client-side (`useEffect` or HOC) で session check (middleware 使えないため)
