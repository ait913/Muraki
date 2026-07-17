---
title: SwiftUI Liquid Glass (iOS 26) — API 実在確認と availability
category: library
tags: [swiftui, ios26, liquid-glass, tabview, apple, xcode]
created: 2026-07-17
project: global
sources:
  - https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
  - https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
  - https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility
  - https://developer.apple.com/support/app-store/
---

## Context
Atender (SwiftUI/iOS) の UI を Apple ネイティブ部品 + Liquid Glass で刷新する設計の事前調査 (Xcode 26.6 / iOS SDK 26.5 実測)。

## What

### ★ 一次ソースは docs より SDK の .swiftinterface
Apple docs より速く正確。シグネチャと `@available` が逐語で読める:

```
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
$SDK/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64-apple-ios-simulator.swiftinterface
$SDK/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64-apple-ios-simulator.swiftinterface
```

**Glass 系の実体は SwiftUI でなく SwiftUICore にある** (`SwiftUICore.Glass`)。SwiftUI 側を grep して「無い」と誤判定しやすい。ButtonStyle だけ SwiftUI 側。

### 実在 API (すべて iOS 26.0+ / visionOS unavailable)
- `func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View`
- `struct Glass`: `.regular` / `.clear` / `.identity`、`.tint(Color?)` / `.interactive(Bool = true)`
- `GlassEffectContainer<Content>(spacing: CGFloat? = nil, content:)`
- `glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID)`
- `glassEffectUnion(id:namespace:)`
- `glassEffectTransition(_:)` — `GlassEffectTransition`: `.matchedGeometry` / `.materialize` / `.identity`
- `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)` / `.buttonStyle(.glass(_ glass: Glass))`
  - **`GlassButtonStyle.init(_ glass:)` は iOS 26.1+**。`.glass(_:)` static func 経由なら 26.0 で通る (実測)
- 周辺: `safeAreaBar(edge:...)`, `backgroundExtensionEffect()`, `scrollEdgeEffectStyle(_:for:)` も iOS 26.0+

### ★ Tab / TabRole は iOS 18.0 であって 26 ではない
よくある誤解。`TabView(selection:content:)` の TabContentBuilder 版・`Tab(value:role:content:label:)`・`TabRole.search`・`.tabViewStyle(.sidebarAdaptable/.tabBarOnly)` はすべて **iOS 18.0+**。
iOS 26 で足されたのは **`.tabBarMinimizeBehavior(_:)`** (`TabBarMinimizeBehavior`: `.automatic` / `.onScrollDown` / `.onScrollUp` / `.never`。automatic 以外は iOS 専用) と **`.tabViewBottomAccessory {}`** (iOS 26.0、`isEnabled:` 版は 26.1) + `EnvironmentValues.tabViewBottomAccessoryPlacement` (`.inline` / `.expanded`)。

### 自動適用 vs 明示 API
- **SDK 26 でビルドするだけで効く**: 標準部品 (bars / sheets / popovers / controls / TabView / NavigationStack / toolbar / Menu / Picker)。「rebuild すれば自動で新しい shape/size を拾う」と公式明記
- **明示 API が要る**: カスタム View の Liquid Glass (`glassEffect`)、tab bar minimize、bottom accessory、background extension
- 公式が明確に警告: **「controls / navigation 要素のカスタム背景を減らせ」** — 自前背景は Liquid Glass や scroll edge effect と干渉する。自前タブバー + `.ultraThinMaterial` はこれに真正面から抵触

### UIDesignRequiresCompatibility (Info.plist, iOS 26.0+)
`YES` = 旧デザインの互換モードで動く。**キー不在 or `NO` が最新 SDK リンク時のデフォルト** (= 新デザイン適用)。
**iOS 27 以降向けにビルドするとシステムはこのキーを無視する** — 恒久的な逃げ道ではなく 1 リリース限りの延命策。

## Why
Liquid Glass は「標準部品を使っていれば only rebuild で乗る」設計。逆に自前描画で標準部品を回避しているアプリは、SDK を上げても一切恩恵が無く、むしろ干渉する側に回る。

## How to apply
- API 実在確認は **swiftinterface を grep → `swiftc -typecheck -target arm64-apple-iosXX.Y-simulator` で実証**。docs より速く確実
- deployment target の影響は **`xcodebuild ... IPHONEOS_DEPLOYMENT_TARGET=26.0`** でファイル無改変のまま実測できる
- iOS 採用率の一次ソースは https://developer.apple.com/support/app-store/ の HTML 内 `data-bar-chart='...'` 属性 (JS レンダリングなので WebFetch では取れない。curl + 属性抽出)
