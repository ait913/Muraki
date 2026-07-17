---
title: OS 版数で分けるのは「質感」だけ。機能・レイアウト・IA を分けない
category: pattern
tags: [ios, availability, liquid-glass, swiftui, design, progressive-enhancement]
created: 2026-07-17
project: global
sources:
  - atender iOS UI 刷新の設計 (2026-07-17)
  - Muraki/knowledge/library/swiftui-liquid-glass-ios26.md
  - Muraki/knowledge/library/ios-glanceable-surfaces-availability.md
---

## Context

iOS 26 の Liquid Glass を採用したいが、deployment target を 26 に上げると
**iPhone install base の 21% を失う** (Apple 公式 2026-06: iOS 26 = 79% / 18 = 14% / それ以前 = 7%)。
target 17 のまま `if #available(iOS 26, *)` で新 API を使う、という判断は自明。

**自明でないのは「何を分岐してよいか」。** ここを決めずに `#available` を書き始めると、
気付いたときには「iOS 26 のユーザーと 18 のユーザーで機能が違うアプリ」になっている。

## What

**判断規則: `#available` で分岐してよいのは質感 (material / motion / システムの自動挙動) だけ。
機能・情報・レイアウト・IA を OS 版数で分けない。**

atender の実例 (「次の授業」を常設表示する要件):

| 案 | 分岐するもの | 判定 |
|---|---|---|
| `.tabViewBottomAccessory` に載せる (iOS 26.0+) | **機能** — 21% のユーザーに「次の授業」が**出なくなる** | **不採用** |
| `safeAreaInset(.bottom)` に自前バーを置き、その**背景だけ** `glassEffect` / `.ultraThinMaterial` で分ける | **質感のみ** — 全 OS で同じ位置に同じ情報が出る。ガラスかすりガラスかだけが違う | **採用** |

- `.tabBarMinimizeBehavior` (iOS 26.0+) は**採用してよい**: スクロールでタブバーが縮むのは
  **additive なシステム挙動**であり、情報を隠さず、無い環境でも何も失われない
- 逆に「iOS 26 だけレイアウトが 1 段少ない」「iOS 26 だけ追加の導線がある」は**同じ機能の 2 実装**を生む。
  仕様が 2 本になり、テストも 2 本になり、片方が腐る

**`#available` の置き場所も規則にする**:

```swift
// Core/DesignSystem/Glass.swift — ★ ここが #available の唯一の置き場所
extension View {
    @ViewBuilder
    func atenderGlass(in shape: some Shape) -> some View {
        if #available(iOS 26.0, *) { self.glassEffect(.regular, in: shape) }
        else { self.background(.ultraThinMaterial, in: shape) }
    }
}
```

Feature 層に `#available` を書かない。**分散すると「26 で何が変わるか」がコードベース全体に散り、
シムを外す日 (= target を上げる日) に追えなくなる。**

## Why

- **`#available` は「新しい方が良い」ではなく「片方のユーザーは見られない」の宣言**。
  質感なら「見られない = 少し地味」で済むが、機能なら「見られない = 使えない」になる
- deployment target を上げる判断は**install base の実測**でしかできない。
  逆に言えば、質感だけを分岐にしておけば **target を上げる日にシムを消すだけで済む** (仕様は 1 本のまま)
- Liquid Glass は特にこの罠が深い: **標準部品 (TabView / NavigationStack / sheet / toolbar) は
  SDK にリンクするだけで自動適用される**ので、そもそも `#available` を書く必要がない。
  `#available` が要るのは `glassEffect` / `tabBarMinimizeBehavior` / `tabViewBottomAccessory` のような
  **明示 API だけ**。「Glass 対応 = `#available` を書くこと」だと誤解すると、
  書かなくていい分岐を大量に書いた上で、肝心の「自前タブバーをやめる」をやらずに終わる

## How to apply

1. **`#available` を書きたくなったら「これは質感か、機能か」を先に判定する。** 機能なら別案を探す
   (atender では bottom accessory → `safeAreaInset` に置き換えて全 OS 共通にした)
2. **シムは 1 ファイルに集約**し、「ここが唯一の置き場所」とコメントに書く
3. **使わない API をシムに置かない** (`GlassEffectContainer` / `glassEffectID` は
   ガラス面が複数あるとき用。1 面しかないなら書かない)
4. **ガラスを敷く面の規則**: 「コンテンツの上に浮くコントロール」にだけ敷く。コンテンツ自体には敷かない。
   Apple は明確に多用を戒めており、かつ**自前背景は Liquid Glass と干渉する**
   (= 自前タブバー + `.ultraThinMaterial` は「Glass が出ない元凶」であって「Glass 風」ではない)
5. **検証は 2 つの OS 版数で**: 新しい方 (ガラスが出ること) と、古い方 (**破綻せず普通に出ること**)。
   後者を撮り忘れると 21% の体験が無検証になる
