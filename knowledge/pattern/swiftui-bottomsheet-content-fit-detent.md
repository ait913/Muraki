---
title: SwiftUI シートをコンテンツ高にフィットさせる — header/content/footer を実測して .height detent
category: pattern
project: atender
tags: [ios, swiftui, bottomsheet, presentationDetents, preferencekey]
created: 2026-07-09
sources:
  - atender apps/ios BottomSheet.swift (2026-07-09 セッション)
---

## Context

atender の共通 `BottomSheet` は `detents: [.large]` や `[.medium, .large]` を使っていた。内容が短いシート(授業の詳細など)では**シート高 > コンテンツ高**になり、下部に巨大な黒い空白ができ、フッタのアクションボタンが遠くに取り残される見た目になった。

## What

シートの中身(ヘッダ + 本文 + フッタ)の実高を `PreferenceKey` で測り、`.presentationDetents([.height(実測値)])` にスナップさせる。概算定数を使わず**全区画を実測**するのがコツ(概算だと差分がそのまま空白になる)。

```swift
// 3つの GeometryReader background で header/content/footer を実測
.background(GeometryReader { p in Color.clear.preference(key: HeaderKey.self, value: p.size.height) })
// ...
private var fittedDetents: Set<PresentationDetent> {
    guard contentH > 0, headerH > 0 else { return fallbackDetents }  // 測定前は呼び出し側 detents
    let target = headerH + contentH + footerH + 8
    return [.height(min(max(target, 180), screenH * 0.92))]  // 下限180/上限92%でクランプ
}
```

- 縦スクロール ScrollView 内の content は「自然高」で測れる(縦は無制約なので GeometryReader が真の内容高を返す)
- 長い内容は 92% でクランプ → 超過分は内部スクロールへ
- PreferenceKey の `static var defaultValue` は Swift 6 concurrency で computed `{ 0 }` にする(stored だと nonisolated global mutable state エラー)

## Why

`ScrollView` は縦に greedy なので、`.frame(maxHeight:)` を付けても detent 高を常に埋めてしまい「hug」しない。detent 自体を実測高にすることで、短い内容は詰まり長い内容はスクロールする、を両立できる。フォーム系シート(テキスト入力あり)でも内容が高いので fitted ≈ 実高になり、キーボード表示時も破綻しない(実機検証済)。

## How to apply

- 「シート下部に空白 / ボタンが遠い」を見たら detent 固定を疑い、この実測フィット方式に置換
- 同じ手は出欠パネルのような**高さ可変の展開パネル**にも適用可(ScrollView を `.frame(height: min(実測, cap))` でフィット)
- 関連: [[swiftui-fixed-minwidth-row-overflows-parent]]
