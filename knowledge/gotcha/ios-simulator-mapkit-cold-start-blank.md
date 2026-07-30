---
title: iOS Simulator の Apple Maps は初回コールドスタートで数十秒タイルが出ない (react-native-maps のバグではない)
category: gotcha
tags: [ios, simulator, mapkit, react-native-maps, expo]
created: 2026-07-30
project: global
sources:
  - "一次実測 2026-07-30: 素の UIKit MKMapView (RN 非経由) を iPhone 16 / iOS 26.5 Simulator で計測"
  - https://github.com/react-native-maps/react-native-maps/issues/5888
  - https://github.com/react-native-maps/react-native-maps/issues/5540
---

## Context

Simulator で「地図が出ない」を見たときに、New Architecture 非互換や Google Maps API キー未設定を
疑う典型的な入口。**本書が扱うのは Simulator 特有の偽陽性だけ**。

★★ **本書は「地図が出ない」の実装バグを免責するものではない。** 発端は omatase の
「イベント作成画面の地図が表示されず、タップした点だけが出る」だったが、**その報告は
TestFlight の実機**で、実機はタイルキャッシュもネットワークも別条件なので**この現象では
説明できない** (2026-07-30 に Leader が確認)。omatase の実機側の真因は別にあり、
`overflow: "hidden"` + `borderRadius` でネイティブ `MKMapView` をクリップしている
`LocationPicker.native.tsx` が筆頭容疑 — 全画面の地図 (`MapCanvas.native.tsx`) では
症状が出ないという差分が根拠。

**したがって本書の使い方は「Simulator で見た症状を実機の症状と混同しない」ため**であって、
「地図が出ないのは Simulator のせい」と結論するためではない。**どこで見たかを必ず確定させる。**

## What

**react-native-maps を一切通さない素の `MKMapView` (UIKit + xcodegen の使い捨てアプリ) でも、
起動直後は同じように真っ白 (クリーム色 + "Maps / Legal" 帰属表示だけ) になる。**
新規 boot した Simulator での実測:

| 経過 | 地図領域の distinct color 数 | 見た目 |
|---|---|---|
| 起動 +15s | 392 | タイル無し・**アノテーションのピンすら出ない** |
| 起動 +約 70s | 29,599 | タイル完全描画・ピン表示 |
| 同アプリを terminate → 再起動 | 29,456 (+4.4s 時点) | **即描画** (geod のタイルキャッシュが温まっている) |

→ 「地図が出ない」は **環境 (Simulator の初回 geod タイル取得)** の症状で、
react-native-maps / Fabric / provider 設定のバグではない。

**「点だけ出る」の説明**: react-native-maps の `<Marker>` にカスタム children を渡すと、
それは実 UIView としてマップ上に載る。タイルは MapKit のレンダラ待ちなので、
**マーカーだけ先に見える状態が正常に起こりうる**。

**タイルが出ない「本物の」既知原因** (issue tracker を通した限り、iOS/Apple Maps で
タイルが出ないバグ報告は存在しない):

- Android の Google Maps で API キー未設定 → 灰色 + Google ロゴ (#5540, #5888)。
  `provider` 未指定なら **iOS=Apple Maps (キー不要) / Android=Google Maps (キー必須)** なので、
  Android だけ壊れる形になる
- iOS で `provider={PROVIDER_GOOGLE}` にした場合はキーが必要になる
- Expo Go で Google Maps を使うと Expo Go 自身の API キーで認証されるため
  `Authorization failure` になる (#5888。dev build では通る)

## Why

MapKit のタイルは `geod` が取得してディスクキャッシュに落とす。Simulator を新規 boot すると
このキャッシュが空で、かつ Simulator の geod は実機より遅い。タイルが 1 枚も無い間、
MKMapView は帰属表示だけを描いた空の view として存在する。

## How to apply

- ★★ **まず「どこで見たか」を確定させる。** Simulator か実機かで原因の候補が入れ替わる。
  実機の報告に本書を当てて「実装バグではない」と結論すると**本物のバグを見逃す** (実際にやりかけた)
- **Simulator で「地図が出ない」を実装バグと分類する前に、素の `MKMapView` を同じ Simulator で 1 回動かす**。
  xcodegen + `xcodebuild -destination 'platform=iOS Simulator,id=<udid>'` + `simctl install/launch`
  + `simctl io screenshot` で 5 分。RN を組む必要はない
- 判定は目視でなく **screenshot の地図領域の distinct color 数** で取る
  (`PIL` で crop → `getcolors`)。数百 = 空、数万 = 描画済
- **1 枚のスクショで結論を出さない**。同じ画面を 15s / 70s で 2 枚撮る
- 他のセッションが使っている Simulator を奪わないこと。`simctl list devices booted` で確認し、
  自分用に別 udid を boot → 終わったら `shutdown` + `uninstall`
