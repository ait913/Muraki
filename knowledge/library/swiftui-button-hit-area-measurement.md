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

## 追記 (2026-07-30): `.background` の挿入位置 — 当たり判定には無関係、塗りの高さには決定的

atender の月カレンダーで「選択日はセル全高をグレー塗り」を足すとき、
`.background` を `.contentShape(Rectangle())` / gesture のどこに挟むと壊れるかを iOS 26.5 実機で実測した
(4 バリアント × 9 点タップ + 中央長押し)。

### 結果: contentShape との前後関係は当たり判定に一切影響しない

| バリアント | frame | 9 点すべて正しいセルに命中 | 長押し |
|---|---|---|---|
| A 背景なし (現行 atender) | 92×78 | ○ | ○ |
| B `.background(...)` → `.contentShape` → gestures | 92×78 | ○ | ○ |
| C `.contentShape` → `.background(...)` → gestures | 92×78 | ○ | ○ |
| D `.background(..., in: RoundedRectangle)` → `.contentShape` → gestures | 92×78 | ○ | ○ |

4 つとも frame・命中パターン・タップ/長押しの弁別まで完全一致。
**`.background` は当たり判定を足しも引きもしない** (本ファイル上部の「background だけで全域が反応する」と整合)。

### ★ 効くのは `.frame(height:)` との前後関係 (視覚の話)

`.background` は「その時点でのビューのサイズ」に敷かれるので、**`.frame(height: rowHeight)` より前に置くと
コンテンツの intrinsic 高さしか塗られない**。実測 (rowHeight=100pt、塗りの見え方):

| 挿入位置 | 塗られる領域 |
|---|---|
| `.padding` より前 | コンテンツのみ (padding も塗られない) |
| `.frame(maxWidth:)` の後・`.frame(height:)` の前 | 幅は全幅、**高さは intrinsic だけ** (上下に地肌が残る) |
| **`.frame(height:)` の後** | **セル全高・全幅** ← 求めている形 |

### 結論: 順序規則

```swift
content
  .padding(...)                      // 1. 余白
  .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
  .frame(height: rowHeight)          // 2. セルの確定サイズ
  .background(fill, in: shape)       // 3. ★ ここ。全高が確定した後に敷く
  .contentShape(Rectangle())         // 4. 当たり判定 (background があっても残して害はない)
  .onLongPressGesture { ... }        // 5. 長押しを内側
  .onTapGesture { ... }              //    タップを外側 (build 14 の競合修正の形を維持)
```

`.background` を 4 の後ろ (contentShape の外) に置いても当たり判定は同じだが、
**規則としては 3 の位置に固定する** — 「サイズ確定 → 塗り → 当たり判定 → gesture」で読み順が意味と一致する。
