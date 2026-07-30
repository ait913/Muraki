---
title: userInterfaceStyle "automatic" + ダークモード端末で iOS ネイティブコントロールが白文字になり消える
category: gotcha
tags: [expo, ios, dark-mode, datetimepicker, userInterfaceStyle, uikit]
created: 2026-07-30
project: global
sources:
  - https://developer.apple.com/tutorials/data/documentation/bundleresources/information-property-list/uiuserinterfacestyle.json
  - https://docs.expo.dev/versions/v57.0.0/config/app/
  - "expo sdk-57: packages/@expo/prebuild-config/build/plugins/unversioned/expo-system-ui/withIosUserInterfaceStyle.js"
  - "expo sdk-57: apps/expo-go/ios/Exponent/Kernel/Views/EXAppViewController.mm"
  - "一次実測 2026-07-30: UIDatePicker(.wheels) を #FFFFFF コンテナに置き、system=Dark で A=inherit / B=overrideUserInterfaceStyle=.light を並べて撮影"
---

## Context

omatase (Expo SDK 57) で日時ピッカーが「白背景に白文字」で読めない、という実機症状。
アプリ側の色トークンは全部ライト固定 (`backgroundColor: "#FFFFFF"` をハードコード) なのに
ネイティブコントロールだけダーク配色になる。

## What

**`app.json` の `userInterfaceStyle: "automatic"` (既定は `"light"` だが omatase は明示的に automatic)
だと、UIKit 由来のコントロールは端末の system appearance に従う。端末がダークモードだと
`UIDatePicker` のホイール文字が白になり、RN 側でハードコードした白いコンテナと同化して消える。**

一次実測 (iPhone 16 / iOS 26.5 Simulator, appearance=dark, UIDatePicker `.wheels` を `#FFFFFF` の
角丸コンテナに配置):

| ケース | 結果 |
|---|---|
| A: override なし (= `automatic`) | ホイールの日付/時刻が**完全に不可視**。選択バンドの薄い帯だけ見える |
| B: 親 VC に `overrideUserInterfaceStyle = .light` | 同じ白コンテナで**黒文字で読める** |

**Expo 側の対応関係 (実装ソースで確認)**:

- ビルド版: `userInterfaceStyle: "light"` → prebuild-config が **Info.plist に
  `UIUserInterfaceStyle = "Light"`** を書く (`'light'→'Light'`, `'dark'→'Dark'`, `'automatic'→'Automatic'`)。
  解決順は `ios.userInterfaceStyle ?? userInterfaceStyle ?? 'light'`。
  Apple 公式の `UIUserInterfaceStyle` = 「force the light user interface style, even when the
  systemwide style is set to dark. Your app will ignore any changes to the systemwide style」
- **Expo Go でも効く**: `EXAppViewController.mm` が manifest の `userInterfaceStyle` を読み、
  アプリの VC に `overrideUserInterfaceStyle` を設定し、`presentViewController:` /
  `addChildViewController:` をフックして提示・子 VC にも伝播させる。さらに
  `RCTOverrideAppearancePreference()` で RN の `Appearance`/`useColorScheme` も揃える。
  ★ ただし Expo Go が読むのは `manifest.userInterfaceStyle` = **トップレベルキー**。
  `ios.userInterfaceStyle` だけ書くとビルド版では効いて Expo Go では効かない可能性がある
- **Android は `expo-system-ui` の install が別途必要** (公式明記)。SDK 57 のピンは `~57.0.2`

## Why

`UIUserInterfaceStyle` は trait collection をアプリ全体で固定するキーで、白/黒を「アプリの色」
としてハードコードした RN 実装とは独立に UIKit の描画色を決める。RN の `StyleSheet` だけを
ライト固定しても UIKit 側の trait は automatic のままなので、両者がズレる。
ズレはダークモード端末でしか出ないため、開発者のライトモード環境では永久に再現しない
(実際に omatase の Simulator 2 台と macOS はいずれも light で、症状が出ていなかった)。

## How to apply

- **ダークテーマを提供しないアプリなら `userInterfaceStyle: "light"` を明示する** (Expo の既定でもある)。
  ピッカー個別の `themeVariant="light"` (datetimepicker の iOS 専用 prop) より上位で、
  アラート・アクションシート・キーボード・カーソル・ActivityIndicator まで一括で効く
- Android も対象なら `npx expo install expo-system-ui` を併せて入れる
- ★ **ライトモードの端末では絶対に再現しないので、確認は `xcrun simctl ui <udid> appearance dark`
  を明示的に叩いてから撮る**。UIKit 混在画面のレビューでは dark 1 枚を必須スクショにする
- 検証は使い捨て xcodegen アプリで十分 (RN を組む必要なし)。`overrideUserInterfaceStyle` の
  有無を上下に並べた 1 画面を撮れば因果が確定する
