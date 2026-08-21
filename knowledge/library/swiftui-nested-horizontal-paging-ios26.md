---
title: SwiftUI 横ページングをタブ+NavigationStack+縦ScrollView の中に入れる (iOS 26 実測)
category: library
tags: [swiftui, ios26, tabview, scrollview, paging, scrolltargetbehavior, calendar]
project: global
created: 2026-07-30
sources:
  - "実測: iPhone 16 / iOS 26.5 Simulator, Xcode 26.6, XCUITest 12 バリアント × 複数回 (2026-07-30)"
  - https://developer.apple.com/documentation/swiftui/scrolltargetbehavior
model-era: opus-4.8
---

## Context

atender の月カレンダーを「指でめくれる」ようにしたい。アプリの構造は
`TabView + .tabItem (Liquid Glass, .tabBarMinimizeBehavior) → NavigationStack → ScrollView(縦)`
で、その**内側**に横ページングを入れる必要があった。使い捨て probe アプリ + XCUITest で全条件を実測した。

## What

### 1. 入れ子にしてもタブバーは二重にならない
`TabView(...).tabViewStyle(.page)` を最上位 TabView の中に入れても
`app.tabBars.count == 1` / `tabBars.buttons.count == 3` のまま (全 12 バリアントで確認)。
`.page` スタイルは tabItem を生成しないので、Liquid Glass のタブバーと干渉しない。
`.tabBarMinimizeBehavior(.onScrollDown)` の誤作動も観測されなかった。

### 2. 縦スクロールと横スワイプは競合しない
pager 領域の内側を縦にドラッグすると、外側の `ScrollView` が正しくスクロールする
(pager の frame.y が 174 → -323 に移動)。14 サンプル中 13 回成功、失敗 1 回はジェスチャ取りこぼし。
`.page` / `.scrollTargetBehavior(.paging)` のどちらでも同じ。

### 3. ★ `.page` は縦 ScrollView の中で高さ 0 に潰れる
`.tabViewStyle(.page)` に `.frame(height:)` を付けないと **pager の実測高さが 0.0pt**。
`.page` は「与えられた高さいっぱい」を取る設計で intrinsic height を持たないため。
→ **`.page` を使うなら固定高が必須**。月ごとに 5 週/6 週で高さが変わるレイアウトとは相性が悪い。

対して `ScrollView(.horizontal)` は、ページ幅を `containerRelativeFrame(.horizontal)` で与えれば
**高さ指定なしで内容の自然高 (実測 348pt) を取る**。
※ ページ幅を `GeometryReader` で測る書き方にすると GeometryReader 自身が intrinsic size を
持たないので高さ 10pt に潰れる。**GeometryReader を使わないのが肝**。

### 4. ★★ 「3ページ・ローリングウィンドウ + index を中央に戻す」は壊れる
前月/当月/翌月の 3 ページだけ持ち、めくったら選択 index を中央 (1) に戻す実装:

| 実装 | 1 スワイプあたりの移動 |
|---|---|
| `.page` + `anchor += delta; index = 1` (アニメーションあり) | **2 ヶ月進む** (2/2 回再現。動画で 0.335s の連続スライドとして目視可能) |
| `.page` + `Transaction.disablesAnimations` で戻す | 1 ヶ月 (2/3 回)、**1/3 回で 2 ヶ月飛ぶ** |
| `.scrollPosition` + `disablesAnimations` で戻す | **2/2 回とも 2 ヶ月飛ぶ** (+1, +2, -2, -2) |

`Transaction.disablesAnimations` は「ちらつき対策」ではなく**正しさの前提条件**であり、
それでも完全には直らない。リセットとページング減速が競合する。

### 5. ★ 解: 窓を広く取って reset を捨てる
当月 ±24 ヶ月 = 49 ページを最初から `ForEach` に並べ、`selection` / `scrollPosition` を
素直に動かすだけ (リセット処理を一切書かない):

| 実装 | 結果 |
|---|---|
| `TabView(.page)` 49 枚 + `.frame(height: 420)` | **2/2 回とも 1 スワイプ = 1 ヶ月** (24→25→26→25→24) |
| `ScrollView(.horizontal)` + `.paging` + `containerRelativeFrame` (高さ指定なし) | **2/2 回とも 1 スワイプ = 1 ヶ月** |

`LazyHStack` / TabView の遅延生成があるので 49 ページでもコストは問題にならない。

### 6. ページインジケータ
`.tabViewStyle(.page(indexDisplayMode: .never))` で `app.pageIndicators.count == 0`。
`.automatic` だと 1。**確実に消せる**。

## Why

`.page` は UIKit の paging scroll view backing で「外から高さを与えられる」前提の部品。
一方 iOS 17 の `.scrollTargetBehavior(.paging)` は普通の `ScrollView` なので
レイアウトの合成規則がそのまま効き、`containerRelativeFrame` と組めば自然高が出る。

リセット方式が壊れるのは、ページング減速の完了と `onChange` 起点の state 書き戻しが
別々のランループで走り、書き戻し後にもう一段ページングが commit されることがあるため。
**「見えている index と data の対応を毎回作り直す」設計自体が競合の温床**で、
窓を広く取れば書き戻しが要らなくなり、競合が構造的に消える。

## How to apply

```swift
// 推奨形: 高さは内容任せ、リセット無し
ScrollView(.horizontal) {
    LazyHStack(spacing: 0) {
        ForEach(months) { m in                    // 当月 ±24 ヶ月を最初から並べる
            MonthGrid(month: m)
                .containerRelativeFrame(.horizontal)   // GeometryReader を使わない
                .id(m.id)
        }
    }
    .scrollTargetLayout()
}
.scrollTargetBehavior(.paging)
.scrollPosition(id: $visibleMonthID)
.scrollIndicators(.hidden)
```

- `.page` を選ぶなら `.frame(height:)` を必ず付ける (付けないと高さ 0)
- **3 ページ + リセットの実装を見たら差し戻す**。窓を広げる方が短く速く正しい
- 検証は XCUITest で `coordinate(withNormalizedOffset:).press(forDuration:thenDragTo:)` を
  4 回 (前2/後2) 打ち、state ラベルを毎回読む。**1 回のスワイプでは 2 段飛びを検出できない**
