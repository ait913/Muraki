---
title: SwiftUI 1 View 内の複数シートは兄弟に並べず単一 .sheet に集約する
category: gotcha
tags: [swiftui, ios, sheet, bottomsheet, atender]
created: 2026-07-01
project: atender
sources: [apps/ios/Atender/Features/Home/SelfTimetableView.swift, apps/ios/Atender/Features/SemesterOverview/SemesterOverviewView.swift]
model-era: opus-4.8
---

## Context
Atender iOS で 1 つの View から複数のボトムシート (DayDetailSheet / BulkEditSheet 等) を出し分けたい場面。共通コンポーネント `BottomSheet` は内部で native `.sheet(isPresented:)` を張る実装。Phase B (SelfTimetableView) と Phase C (SemesterOverviewView) で同型の defect が再発した。

## What
`Group { BottomSheet(isPresented: A){...}; BottomSheet(isPresented: B){...} }` のように **複数の `.sheet` を兄弟で同一階層に並べると、SwiftUI は 1 つしか発火しない** (残りは isPresented を true にしても開かない)。Phase C ではカレンダーの日タップで `activeSheet = .day` になっても DayDetailSheet が開かなかった (配線は正しいのに)。FullScreenModal は別機構なので影響を受けない。

## Why
SwiftUI の `.sheet(isPresented:)` は 1 つの presentation スロットを消費する。同一の presentation context (兄弟ビュー群) に複数の sheet modifier がぶら下がると、最初の 1 つだけがアクティブな presentation として扱われ、他は無視される。ビュー階層を分けない限り複数同時 (または切替) は成立しない。

## How to apply
`activeSheet: SomeEnum?` を単一の状態に持ち、**`@ViewBuilder` の `switch` で case ごとにその時 1 つだけシートを返す**。全 case が共有する `Binding<Bool>` (`get: activeSheet != nil`, `set: if !$0 { activeSheet = nil }`) を各シートの `isPresented` に渡す。これで tree 内に `.sheet` が常に高々 1 つしか存在せず確実に発火する。

```swift
@ViewBuilder private var sheetHost: some View {
    switch activeSheet {
    case .day(let date): BottomSheet(isPresented: activeSheetBinding) { DayDetailSheet(...) }
    case .bulk:          BottomSheet(isPresented: activeSheetBinding) { BulkEditSheet(...) }
    case nil:            EmptyView()
    }
}
private var activeSheetBinding: Binding<Bool> {
    Binding(get: { activeSheet != nil }, set: { if !$0 { activeSheet = nil } })
}
```

参照実装: `SelfTimetableView.activeSheetView(...)` (Phase B で確立)。新しいマルチシート画面を作るときは最初からこの集約形にする (兄弟 `.sheet` を書かない)。

**1 枚目を閉じずに 2 枚目を重ねたい場合 (切替でなく積む)** は、2 枚目の `.sheet` (= `BottomSheet`) を **1 枚目の content の内側** (`.background { ... }`) に置く。`ZStack { BottomSheet(1 枚目) ; BottomSheet(2 枚目) }` は兄弟なので同じ defect になる — atender の `MeetingEditModal` が「＋ 科目を追加」で `CourseEditModal` を兄弟に置いていて、1 枚目提示中は何も起きなかった (build 19 で修正、`.designs/20261007-build19-semester-rollover.md` §5)。参照実装: `DayDetailSheet` の `.background { sheetHost }`。自己提示型の部品 (`Color.clear.sheet(...)`) は「どの階層に置かれたか」で提示元が決まるので、呼び出し側が ZStack の兄弟に並べると壊れる。
