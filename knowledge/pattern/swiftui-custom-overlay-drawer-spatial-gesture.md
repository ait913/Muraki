---
title: SwiftUI 折りたたみドロワー/せり上がりパネルは native sheet でなくカスタム overlay + ジェスチャー空間分離で作る
category: pattern
project: atender
tags: [swiftui, ios, drawer, gesture, overlay, sheet, scrollview]
created: 2026-07-22
sources:
  - atender .designs/20260722-home-collapsible-layout.md
  - knowledge/gotcha/swiftui-multiple-sibling-sheets-only-one-fires.md
---

## Context

既存グリッド (縦 ScrollView + 内部に水平 drag する月カレンダー) の上に、上端プルダウン・ドロワーや下端せり上がりパネルを載せたい。native `.sheet` / `presentationDetents` は (a) 下端専用で上端ドロワーが作れず、(b) presentation スロットを 1 個消費するので同一 View ツリーの単一 `.sheet` 集約 (activeSheet) と衝突する。

## What

**カスタム `.overlay(alignment:)` + `offset(y:)`/`transition(.move(edge:))` + `DragGesture` + `withAnimation` で作る。** 3 つの設計判断が肝:

1. **native sheet を使わない** → presentation スロットを消費しないので、同じ View が別途持つ単一 `.sheet(activeSheet)` と共存できる (衝突しない)。
2. **ジェスチャー競合は priority 調停でなく空間分離で解く** → drag 検知を「グラバー帯 (グリッドの外・高さ 36-44pt)」に限定する。グリッド本体の縦 ScrollView・水平 drag と**領域が交わらない**ので `simultaneousGesture`/`highPriorityGesture` の調停が不要。全画面 drag にすると ScrollView と月送りを壊す。
3. **開閉判定を純関数に切り出す** → `resolve(isExpanded:translationHeight:translationWidth:)` を作り、`abs(height)>abs(width)` の縦優位ガード + 閾値 (40pt) を入れる。横優位 drag は現状維持で返す (水平月送りの誤爆防止)。この純関数だけを XCTest で網羅でき、DragGesture を UI 発火させずに済む。

```swift
static func resolve(isExpanded: Bool, translationHeight: CGFloat, translationWidth: CGFloat) -> Bool {
    guard abs(translationHeight) > abs(translationWidth) else { return isExpanded }  // 横優位は無視
    if !isExpanded, translationHeight >  threshold { return true }
    if  isExpanded, translationHeight < -threshold { return false }
    return isExpanded
}
```

- overlay は **viewport 固定の親 (ZStack/最外殻)** に付ける。グリッドの `ScrollView` の内側に付けると FAB/パネルがスクロールで流れる (別 note §39)。
- せり出し/せり上がりは `frame(height:)` アニメでなく `offset(y:)`+`opacity` / `transition(.move(edge:))`。height アニメは中身の再レイアウトで破綻する。
- グラバー意匠と高さ実測 PreferenceKey は既存 sheet 実装から流用可 (`Capsule().frame(width:42,height:5)` 等)。本体ロジックだけ作り直す。
- 面の質感は不透明自前背景を避け `.glassEffect` 系 (Liquid Glass) を敷く。scrollEdgeEffect との干渉は実機でしか確定しないので検証項目に入れる。Glass 面には影を重ねない。

## Why

`.sheet(isPresented:)` は 1 presentation スロット制約があり (sibling sheet が 1 つしか発火しない既知 gotcha)、上端/in-place の可変パネルには元々向かない。カスタム overlay なら位置・方向・開閉曲線を完全制御でき、既存 sheet 集約とも独立。ジェスチャー競合を priority で解こうとすると調停が脆く再現しにくいバグになるが、hit area を物理的に分ければ競合そのものが消える。

## How to apply

- 「native sheet が下端専用/スロット衝突で使えない」可変パネルはこの型。
- drag を載せる前に「その領域の下に既存の scroll/drag があるか」を確認し、あるなら hit area を帯に絞って空間分離する (priority 調停は最後の手段)。
- 開閉・既定展開・畳み判定は純関数化して #番号付き挙動仕様にし、Reviewer がテストできる形にする。
- 関連: [[swiftui-multiple-sibling-sheets-only-one-fires]] / [[swiftui-bottomsheet-content-fit-detent]]
