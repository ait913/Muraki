---
title: 「描かれないこと」の検証はレンダ差分の**対**で書く (ImageRenderer + PNG 等値)
category: pattern
tags: [ios, swiftui, imagerenderer, testing, negative-assertion, reviewer, ui-test]
created: 2026-07-30
project: atender
sources:
  - "atender .designs/20260730-calendar-ui-defects.md §1.4 / §9-B (当月外セルに chip/ドットを描かない)"
  - "実測: AtenderTests/CalendarMonthRenderTests.swift (iPhone 16 / iOS 18.2 Simulator, scale=3)"
---

## Context

UI 設計は「当月外の日はイベント chip / ステータスドットを**描かない**」のような
**否定形の描画規則**をよく持つ。純関数 (`showsDayContent(date:monthFirst:)`) を
テストしても「その関数が View に配線されているか」は 1 ミリも証明できない
(role note 43 の系譜)。かといって pixel を直接当てにいくと破綻する:

- chip は不透明度・tint・ガラス合成で色が変わり、「この RGB があるか」で書けない
- セルの座標はカード padding / 行高 / スケールに依存し、テストが幾何の写経になる

## What

**3 枚レンダして 2 本の assert を書く**と、色も座標も知らずに済む。

```swift
let empty   = render(events: [], summaries: [:])                  // 何も足さない
let outside = render(events: [ev(date: 当月外)], summaries: [:])  // 禁止スロットに足す
let inside  = render(events: [ev(date: 当月内)], summaries: [:])  // 許可スロットに足す

XCTAssertNotEqual(empty, inside,  "許可スロットで描画が変わらない = 計測が無力")
XCTAssertEqual(   empty, outside, "禁止スロットに描かれている")
```

`render` は `ImageRenderer(content:)` の `uiImage.pngData()` を返すだけ。
scale と `proposedSize` を固定すれば PNG は決定的で、`Data` の等値比較で足りる。

atender では `CalendarMonth` に対して #R1 (event chip) / #R2 (status dot) /
#R3 (chip 5 件 + `+N` overflow + dot の全部盛り) の 3 本がこの形で書け、
`showsDayContent` の判定を `==` → `!=` に変異させると **3 本とも赤くなった**
(= View への配線を実際に見ている)。

## Why

- **`XCTAssertEqual(empty, outside)` を単独で書くと、レンダが常に同じ結果 (真っ白 / 失敗)
  でも緑になる。** 「byte-identical は no-op と『ハーネスが迷子』を区別しない」
  (gotcha/screenshot-byte-identity-conflates-noop-tap-with-lost-harness.md) の同型。
  対になる `NotEqual` が**そのハーネスが差分を検出できること**を同じランで証明する。
- 色・座標を assert しないので、デザイントークンの変更や端末幅の違いでテストが壊れない。
- 「禁止スロット」に**溢れそうなほど大量**に足しても不変であることまで書けば、
  overflow 表示 (`+N`) の抜けも同時に塞げる。

## How to apply

- 否定形の描画規則 (「当月外は描かない」「未来日は破線を出さない」「ゲスト時はマスクする」)
  を見つけたら、まずこの 3 枚レンダに落とせないか考える。
- View が環境注入を必要とすると使えない。**設計側で「その View を純 View に保つ」ことが
  テスト可能性そのもの**になる (atender は `@Environment(AppEnvironment.self)` を消した結果、
  `AttendanceCalendar` が単体レンダ可能になり #R5/#R6 が書けた)。
- 逆に言うと、レンダ差分で分かるのは「変わった / 変わらない」だけ。
  **「範囲外のセル*だけ*が消えた」ような位置特定は依然として目視ゲート**なので、
  判定にはカバー範囲を明記する。
- 列配置そのものを測りたいときは PNG でなく `GeometryReader` を `.background` に差し、
  `proxy.frame(in: .named(...))` を body 評価中に記録して `ImageRenderer` で
  レイアウトを走らせる (同 PJ `CalendarColumnGeometryTests`)。
  **感度コントロールは「修正前の View 構造を probe 側に再現して壊れることを見せる」**。
