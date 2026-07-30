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

シートの中身の実高を `PreferenceKey` で測り、`.presentationDetents([.height(実測値)])` にスナップさせる。概算定数を使わず**実測**するのがコツ(概算だと差分がそのまま空白になる)。

★ **測るのは「自前ヘッダの高さ」ではなく「シート最上端からコンテンツ上端までの距離 (= chrome 高)」**。自前ヘッダを測る形にすると、ヘッダをシステム描画 (sheet 内 `NavigationStack` の nav bar) に置き換えた瞬間に測れなくなり、フォールバックの `[.medium,.large]` に無言で退行する(atender 2026-07-30 にこれで規格変更が詰まりかけた)。コンテンツ上端の y を測る形なら、上に何が乗っていても(グラバー / nav bar / バナー)自動で追従する。

```swift
// content 側の GeometryReader 1 個から 2 つの preference を出す
.background(GeometryReader { p in
    Color.clear
        .preference(key: ContentKey.self, value: p.size.height)
        .preference(key: ChromeKey.self,  value: p.frame(in: .named(rootSpace)).minY)  // ★ chrome 高
})
// シート最上端の View に .coordinateSpace(.named(rootSpace))

private var fittedDetents: Set<PresentationDetent> {
    guard chromeH > 0, contentH > 0 else { return fallbackDetents }  // 測定前は呼び出し側 detents
    let target = chromeH + contentH + footerH + 8
    return [.height(min(max(target, 180), screenH * 0.92))]  // 下限180/上限92%でクランプ
}
```

- 縦スクロール ScrollView 内の content は「自然高」で測れる(縦は無制約なので GeometryReader が真の内容高を返す)
- ★ reader が ScrollView の**中**にあるので、スクロールすると `minY` が減る → `chromeH = max(chromeH, new)` で静止時の値に張り付かせ、上限 (例 160pt) でクランプする。`.scrollBounceBehavior(.basedOnSize)` を付けて「収まるときは弾まない」ようにするとさらに安定
- 長い内容は 92% でクランプ → 超過分は内部スクロールへ
- ★ **`NavigationStack` で push した先の高さは測らない**。preference が stack を越えて伝播する保証が無く、「測れたつもりで 0」= フォームが潰れる方向に倒れる。push 中は無条件に上限 (92%) にするほうが安全 (フォームは元々スクロールする長さ)
- 計算は純関数 (`fittedHeight(chrome:content:footer:screenHeight:isPushed:) -> CGFloat?`) に出す。View 層は観測できないが、境界 (未測定 → nil / 下限 / 上限 / push 中) は全部ユニットテストで固定できる
- PreferenceKey の `static var defaultValue` は Swift 6 concurrency で computed `{ 0 }` にする(stored だと nonisolated global mutable state エラー)

## Why

`ScrollView` は縦に greedy なので、`.frame(maxHeight:)` を付けても detent 高を常に埋めてしまい「hug」しない。detent 自体を実測高にすることで、短い内容は詰まり長い内容はスクロールする、を両立できる。フォーム系シート(テキスト入力あり)でも内容が高いので fitted ≈ 実高になり、キーボード表示時も破綻しない(実機検証済)。

## How to apply

- 「シート下部に空白 / ボタンが遠い」を見たら detent 固定を疑い、この実測フィット方式に置換
- 同じ手は出欠パネルのような**高さ可変の展開パネル**にも適用可(ScrollView を `.frame(height: min(実測, cap))` でフィット)
- 関連: [[swiftui-fixed-minwidth-row-overflows-parent]]
