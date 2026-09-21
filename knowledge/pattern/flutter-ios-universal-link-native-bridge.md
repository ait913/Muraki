---
title: Flutter iOS の Universal Link は SceneDelegate override + MethodChannel で受け、FlutterDeepLinkingEnabled=false にする
category: pattern
project: global
tags: [flutter, ios, universal-link, deep-link, scene-delegate, go_router]
created: 2026-09-22
sources:
  - Muraki/projects/bloom/.designs/20260922-ui-fixes-batch.md §3
  - Flutter 3.47.0 ios-profile Flutter.framework (nm 実測)
---

## Context

Flutter 3.47 (UIScene ライフサイクル、`FlutterSceneDelegate` 継承) のアプリで、招待 URL (`https://host/i/<token>`) の Universal Link を「route にせず Dart のフローに渡したい」(未サインインなら保留、サインイン後に消費)。既に通知タップ用の自前ブリッジ (`NotifBridge`: pending バッファ + MethodChannel) がある。

## What

- `app_links` 等のパッケージは足さない。自前 `SceneDelegate` で `scene(_:willConnectTo:options:)` (cold start、`connectionOptions.userActivities`) と `scene(_:continue:)` (warm) を `override` し、`NSUserActivityTypeBrowsingWeb` の `webpageURL` を MethodChannel (`invokeMethod("link", url)`、Dart 未接続なら pending) で渡す。
- `FlutterSceneDelegate` が両メソッドを実装していることは engine バイナリで確認できる: `nm -U .../Flutter.framework/Flutter | grep 'FlutterSceneDelegate scene:continueUserActivity'`。ヘッダーには出ないが `override` は通る。
- **`Info.plist` に `FlutterDeepLinkingEnabled = false` を必ず入れる。** Flutter 3.27+ は既定 true で、engine が URL path を `RouteInformationProvider` に流し込み、go_router に該当 route が無いとエラー画面になる。

## Why

- リンクを go_router の route にすると `redirect` (未サインイン → `/onboarding`) で token が落ちる。redirect に副作用 (kv 保存) を書くのは避けたい。
- プラグインが scene 転送 (`FlutterSceneLifeCycleDelegate`) に対応しているかは pub-cache を開かないと分からない。自前なら 30 行で済み、既存ブリッジと同じ作法になる。

## How to apply

1. Swift: 既存の `SceneDelegate.swift` に `final class LinkBridge` を同居 (pbxproj を触らない)。`AppDelegate.didInitializeImplicitFlutterEngine` で `attach(to: messenger)`。
2. Dart: `LinkBridge` (`attach()` / `onLink` / `takePendingLink()`) を `MaterialApp` の上の Widget (`BloomApp`) で購読。初回は `takePendingLink` で cold start 分を回収。
3. 受けた URL は開かない。純関数で token を抽出し自 API へ (`gotcha/invite-deeplink-qr-host-check-is-noop.md`)。
4. `Runner.entitlements` に `com.apple.developer.associated-domains: applinks:<host>`、developer.apple.com の App ID 側でも Associated Domains capability を ON。
