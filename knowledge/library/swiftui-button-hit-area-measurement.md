---
title: SwiftUI Button の当たり判定は clipShape/background では削れない (実測)
category: library
tags: [swiftui, ios, hit-testing, contentShape, clipShape, xcuitest]
created: 2026-07-30
project: atender
sources:
  - "実測: iPhone 16 / iOS 18.2 Simulator / Xcode 16 系 (2026-07-30)"
  - "https://developer.apple.com/tutorials/data/documentation/swiftui/view/clipshape(_:style:).json"
---

## Context

atender の学期カレンダーで「押せるセルと押せないセルがある」という実機 FB を切り分けた。
日セルは `ZStack { Color; slices }.clipShape(Circle())` を Button の label にしていたので、
「円の外 (正方形の四隅) が死んでいるのでは」という仮説を立てた。
また同 PJ の build 13 では、ホームカレンダーの「上部しか押せない」を
`.contentShape(Rectangle())` 追加で直した実績があった。

## What

XCUITest で `coordinate(withNormalizedOffset:)` を使い、セルの中心・四隅・上下端を
逐一叩いて「どのボタンが反応したか」を実測した結果:

| label の構造 | 中心 | 四隅 | 上下端 |
|---|---|---|---|
| `ZStack{Color}.clipShape(Circle()).aspectRatio(1,.fit)` | ヒット | **ヒット** | ヒット |
| `VStack{...}.frame(height:).background(Color)` | ヒット | ヒット | ヒット |
| 上 + `.contentShape(Rectangle())` | ヒット | ヒット | ヒット |

- **`clipShape(Circle())` は描画だけを切り、当たり判定は削らない。** 正方形レイアウト枠の全域が反応する
- `.background(Color)` だけで全面を埋めた Button も全域が反応する
- LazyVGrid (7列 spacing 3) に並べた 21 セル × 6 点 = 126 タップで死に領域 **0 件**

Apple の `clipShape(_:style:)` docs は hit testing に一切言及していない (abstract/discussion とも
「描画を切る」だけ)。つまり「clipShape はタップも切る」は**ドキュメント上の根拠がない俗説**。

## Why

`contentShape` が必要になるのは「レイアウト枠の中に描画も背景も無い透明領域がある」ケース
(例: `Spacer()` だけの領域、`HStack` の隙間)。塗りのある `Color` / `background` が枠を
埋めていれば追加は不要。`.contentShape` を足して直った事例は、実際には別の要因
(内側の `clipped()`、`simultaneousGesture` の競合、枠より小さい描画) が絡んでいることがある。

## How to apply

- 「タップ領域が狭い」系の実機 FB を**構造の目視だけで断定しない**。
  scratchpad に xcodegen で app + UITest ターゲットを作り、疑わしい label 構造を逐語コピーして
  `coordinate(withNormalizedOffset:).tap()` で叩けば 3 分で白黒がつく (本体 repo を汚さない)
- 判定は「タップ後に state が変わったか」で見る。**必ず毎回 log を reset してから叩く**
  (reset しないと前回の値が残り、無反応でも「ヒットした」と誤読する — 実際に 1 回踏んだ)
- タップ領域の実サイズは `GeometryReader` を `.background` に差して読ませるのが確実。
  XCUI の `element.frame` は overlay の stroke 分だけ大きく出たり、
  LazyVGrid の画面外セルでコンテナ枠に化けたりする
- xcodegen で UITest ターゲットを作るときは `GENERATE_INFOPLIST_FILE: YES` が必要
  (無いと `Cannot code sign because the target does not have an Info.plist file` で落ちる)。
  app ターゲットのソースを `main.swift` にすると `'main' attribute cannot be used in a
  module that contains top-level code` になるのでファイル名を変える
