---
title: 外側の accessibilityIdentifier が共通部品の検証フックを潰す (XCUITest から掴めなくなる)
category: gotcha
project: atender
tags: [ios, swiftui, xcuitest, accessibility, testability, reviewer, design-doc]
created: 2026-07-30
sources:
  - "atender build 16 P4 Reviewer 検証 (2026-07-30) — 設計 §5.2 / §7.3-c"
  - "実測: iPhone 16 / iOS 18.2 Simulator の app.debugDescription"
---

## Context

共通部品 (`CalendarDaySheet`) の設計 doc が **検証フックとして identifier を規定する**のはよくある形:

- §5.2「`.accessibilityIdentifier("calendar-day-sheet")` をシート本体に、`"day-sheet-add"` を追加ボタンに」
- §7.3-c「タップした結果 `calendar-day-sheet` が存在することを assert する形にする」

ところがアダプタ (`PersonalDaySheet`) が**その外側**で `.accessibilityIdentifier("personal-day-sheet")` を付けていると、
**内側の identifier はアクセシビリティツリーに 1 つも現れない**。

## What

実測 (`app.debugDescription`): 日別シート内の**全 leaf** が `identifier: 'personal-day-sheet'` を持ち、
`app.descendants(matching: .any).matching(identifier: "calendar-day-sheet").count == 0`。
`day-sheet-add` を付けたはずの追加ボタンも `personal-day-sheet` になっていた。

- SwiftUI の `accessibilityIdentifier` は**子孫へ伝播**し、**外側の指定が内側を上書きする**
- したがって「部品側に付けた identifier」は、呼び出し側が同じ modifier を使った瞬間に消える
- **ラベルや見た目は無傷なので、実機では誰も気付かない**。壊れるのは自動検証の掴み所だけ

## Why

`0 failures` では検出できない。ユニットテストは identifier を見ないし、
XCUITest 側は「identifier が無い」= `exists == false` を**実装が壊れた**とも**識別子が潰れた**とも読める
(role note 59 の byte 一致と同型の多義性)。

## How to apply

- **Reviewer**: 設計 doc が identifier を検証フックに指名していたら、**まず `app.debugDescription` を 1 回吐かせて実在を確認する**。
  無かったら「シートが開かない」と誤帰属せず、`sheet-close` 等の**別の掴み所**で挙動を確かめ、
  identifier の不在は**独立した 1 本のテスト**に切り出して報告する (挙動 GREEN と契約 RED を混ぜない)。
- **Architect**: 「共通部品に identifier」を書くなら「**アダプタ側は identifier を付けない**」を同じ節に明記する。
  逆に画面別に分けたいなら、部品側の identifier に prefix を渡す API (`identifierPrefix: String`) にする。
- **Developer**: 既存の画面固有 identifier を残したまま共通部品を差し込むと、部品側の identifier が黙って死ぬ。
- 代替の頑丈な掴み所: nav bar のタイトル文字列 (`label MATCHES "^[0-9]+月[0-9]+日.*"`) や
  ボタンの `accessibilityIdentifier` を**leaf の Button に直接**付けたもの (leaf 同士なら最内が残る場合もあるが、
  外側の container 指定があると同じく潰れるので過信しない)。
