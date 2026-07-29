---
title: SwiftUI の等幅グリッドは `minWidth: 0` が要る — `.frame(maxWidth: .infinity)` だけでは列がガタつく
category: gotcha
project: atender
tags: [ios, swiftui, layout, hstack, lazyvgrid, grid, hairline, pixel-snapping]
created: 2026-07-30
sources:
  - atender apps/ios/Atender/Features/Calendar/PersonalCalendar.swift (build 13 実機FB)
  - ImageRenderer による実測 (macOS, scale=3)
---

## Context

atender の月カレンダー (7列×6行) が実機で「表の線がズレてる」と報告された。各セルが
`.frame(maxWidth: .infinity)` で等幅化され、自分の上辺 / 左辺に 0.5pt の hairline を
overlay で描く構造。行ごとに縦罫線の x がバラバラ、端の列が見切れる。

## What

**3 つが独立に効いていた。それぞれ実測済 (ImageRenderer + GeometryReader)。**

### 1. `.frame(maxWidth: .infinity)` は最小幅を 0 にしない

flexible frame は `minWidth` を省くと**子の intrinsic 最小幅がそのまま下限として残る**。
HStack はその下限を尊重するので、**中身の多いセルだけ太り、残りが痩せる**。

コンテナ 345pt / 7列 (等分なら 49.286pt) での実測:

| セルの中身 | intrinsic 最小幅 |
|---|---|
| 日付丸(24pt)のみ | 30pt |
| + ドット1個 | 44pt |
| + ドット2個 | **52pt** |
| + ドット3個 | **60pt** |

1 セルでも最小幅が等分値を超えると、その行だけ `60 / 47.5×6` のように配分が変わる。
超過セルが多い行は合計が親幅を超え、HStack が**中央寄せで溢れる** (x が負になり両端が
clipShape で切れる)。結果、**行ごとに縦罫線の x が最大 7pt 以上ズレる**。

修正案の実測比較 (コンテナ 345pt):

| 方式 | 結果 |
|---|---|
| `.frame(maxWidth: .infinity)` (現状) | 行ごとにバラバラ・溢れる |
| **`.frame(minWidth: 0, maxWidth: .infinity)`** | 全行 49.286pt で揃う ✅ (中身は clip される) |
| `LazyVGrid(columns: [.flexible(minimum: 0)])` | **効かない**。セルが列枠を超えて隣と重なる ❌ |
| 明示幅 `.frame(width:)` を px 丸め + 余り分配 | 全行揃う + **ピクセル境界にも乗る** ✅✅ |

CSS Grid の `1fr` も既定 `min-width: auto` で同じ罠がある。Web 側は `min-w-0` を明示して
潰していた — **`minWidth: 0` はその SwiftUI 版**。

### 2. 0.5pt の hairline は 0.5pt では描かれない (@3x)

0.5pt = 1.5 device px。ラスタライズ時に**開始位置がピクセル境界なら 2px、半ピクセル
境界なら 1px** に丸められる (実測: 同じ 0.5pt が ink 142 と ink 71)。つまり実効の太さが
**2 倍ばらつく**。行高が `(available - 42) / 6` のような分数だと、行ごとに 2px/1px が
交互になり「横罫線の位置が揃っていない」ように見える (rowHeight 92.1667 で実測、
rowHeight 93.0 なら全行 2px で均一)。

### 3. 等分値そのものがピクセルに乗らない

345/7 = 49.2857pt → @3x で 147.857px。7 本の縦線が .857/.714/.571/.429/.286/.143 と
全部違う端数に落ちるので、**等幅にした後でも線の濃さが列ごとに違う**。
機種別: 393pt 幅 → 49.2857 (✗) / 402 → 50.5714 (✗) / 440 → **56.0 (✓割り切れる)**。
つまり**同じコードが Pro Max だけ綺麗に見える**。

## Why

- SwiftUI の flexible frame は「提案を min/max で clamp する」だけで、子の最小幅を
  切り捨てはしない。等幅を保証しているつもりが、実際は「最低これだけは要る」の総和で
  配分が決まっている
- SwiftUI の描画はレイアウト値をピクセル丸めしない。ヘアラインの見え方は
  `位置 × scale` の端数に完全に依存する

## How to apply

- **7 列カレンダー・時間割のような「等幅であること自体が意味を持つ」グリッドでは、
  等分幅を自分で計算して `.frame(width:)` で渡す。** `floor(親幅 × scale / 列数) / scale`
  で device pixel に丸め、余り px を先頭から 1px ずつ配る。`@Environment(\.displayScale)`
  を使う
- 最低でも **`.frame(minWidth: 0, maxWidth: .infinity)`**。`minWidth: 0` の省略は等幅の
  保証にならない
- **罫線はセルに持たせない。** グリッド全体で 1 枚のレイヤー (`Canvas` / 1 個の overlay)
  として、丸めた x/y に描く。セルが自分の辺を描く方式は、幅が 1pt でも違えば即破綻する
- ヘアラインを使うなら太さは `1 / displayScale` (= @3x なら 0.333pt) にする。0.5pt は
  どの scale でもピクセル境界に乗らない
- **「1 機種で綺麗、別機種で汚い」は割り切れるかどうかを疑う。** 論理幅から padding を
  引いた実値を列数で割って端数を出す。これは 30 秒で判定できる
- 検証は実機を待たず **macOS の `ImageRenderer` + `GeometryReader` で offscreen 実測**
  できる。SwiftUI のレイアウト計算はプラットフォーム共通なので、セルの実フレームと
  ラスタライズ後のピクセルを両方測れる (atender ではこれで 10 分で断定した)
