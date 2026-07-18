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

## Tab bar icon サイズ / ラベル間隔は iOS 26 Liquid Glass では実質制御不可
Atender の「タブアイコンがでかい・文字と近い」要望調査 (2026-07-18)。native `TabView` + `.tabItem(Label(...))` 前提。

### (a) アイコンサイズ = 制御不可
- **first-class な tab bar アイコンの point-size / SF Symbol scale 指定 API がそもそも存在しない**。`UIBarItem` に `preferredSymbolConfiguration` は無い (SDK 26.5 header 実確認)。従来はアイコンの image 実寸から決まり、`imageInsets` (UIEdgeInsets) で位置ずらしのみ
- **SwiftUI `.tabItem { Label(...).imageScale(.small) / .font(...) }` は無視される**。tabItem の Label に効かないのは iOS 26 以前からの既知挙動 (通説は真)。tab bar 装飾は UIKit の appearance proxy 経由が唯一の道だった
- iOS 26 では **`UITabBar.appearance()` / `UITabBarAppearance` の override 自体が「effectively ignored」** と複数の実務報告 + Apple DTS (forums/thread/821539, Albert Pascual) が明言 (「eventually that override will stop working」)。SwiftUI iOS 26 TabView が UITabBar backing かも不確実 (どちらにせよ観測結果は「効かない」)

### (b) アイコン↔ラベル間隔 = ほぼ制御不可 (API は生きているが LG 下で効かない)
- `titlePositionAdjustment` (UIOffset) は **SDK 26.5 header に健在・deprecated ではない** (`UITabBarItem` ios(5.0) / `UITabBarItemStateAppearance` ios(13.0))。`titleTextAttributes` で font 指定も宣言上は可能
- **が、これも appearance override 経路なので Liquid Glass 下では効かない可能性が高い**。ランタイム実機/シミュレータでの効果検証は未実施 = ★未確定。header は「コンパイルが通る」ことの証明であって「描画に反映される」証明ではない

### iOS 26 の思想: tab bar 寸法はシステム所有
- HIG「tab bar icons automatically adapt to different contexts」「compact ではアイコンがラベルの上、regular では横並び」。iPhone portrait は compact = アイコン上/ラベル下。tvOS 節では「height 68pt / top 46pt は変更不可」と明記され、**Apple が tab bar 寸法をハードコードする思想が一貫**
- 選択 capsule は Liquid Glass 有効時 **強制** (DTS 明言)。`selectionIndicatorTintColor/Image` も無視されがち

### 取りうる手 (トレードオフ)
1. **native のまま微調整** → 実質できない。ユーザーの「でかい/近い」は iOS 26 のシステムメトリクスであってバグではない
2. **自前描画 tab bar に戻す** → 完全制御できるが **Liquid Glass は自前描画では一切出ない**。かつ自前背景 (`.ultraThinMaterial` 等) は LG / scroll edge effect と干渉すると公式が警告 (本ファイル上部参照)
3. **tab bar だけ LG を opt-out** (`UIDesignRequiresCompatibility` 等) → UITabBar appearance 制御が復活するが、そのバーの glass は失う

### ★ 一次実測で確定 (2026-07-18、Leader プローブ)
二次情報だった「appearance override は効かない」を **本番経路プローブで独立検証済**。atender の `MainTabView.init()` に `UITabBarItemAppearance` を仕込み iOS 26.5 実機ビルドで撮影:
- `item.normal.iconColor = .systemRed` → **無視** (選択アイコンはピクセル実測 rgb(20,141,221) = AccentColor azure のまま、赤くならない)
- `titlePositionAdjustment = UIOffset(vertical: 12)` → **無視** (ラベル位置不変)
- `standardAppearance` / `scrollEdgeAppearance` の両方に stacked/inline/compactInline すべて設定しても効かず

→ **結論確定: iOS 26 Liquid Glass タブバーでは `UITabBarAppearance` 系の override が丸ごと無視される。** アイコンサイズ (API 無し = header 一次確認) もラベル間隔 (`titlePositionAdjustment` 無視 = 実測) も native では制御不能。上記トレードオフ 3 択が唯一の選択肢で、これは「glass を取るか寸法制御を取るか」の**プロダクト判断**。
