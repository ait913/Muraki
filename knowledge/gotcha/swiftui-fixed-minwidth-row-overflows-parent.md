---
title: SwiftUI で固定 minWidth のボタン群が幅超過すると親ごと画面幅を突破して全体が左シフトする
category: gotcha
project: atender
tags: [ios, swiftui, layout, hstack, overflow]
created: 2026-07-09
sources:
  - atender apps/ios SelfTodayCTA (2026-07-09 セッション)
---

## Context

atender ホームの出欠 CTA を展開すると、パネル内のステータスボタン(出/欠/公/遅/早/休 の6個)が並ぶ。展開した瞬間、**画面全体が左にずれて両端が見切れる**バグが出た(「自分」チップや学期名が画面外へ)。

## What

`HStack(spacing: s3) { ForEach(6 statuses) { Button.frame(minWidth: 40).padding(.horizontal, s2) } }` のように、**固定 minWidth + padding のボタンを横並び**にすると、6個の合計インセット幅が利用可能幅を超える。

SwiftUI の HStack は子の intrinsic 最小幅を満たそうとするため、行が親コンテナの幅を**押し広げる**。この CTA は `ZStack(alignment:.bottom)` でホーム全体と同じ階層にあったため、**CTA が画面幅を超える → ZStack ごと画面幅を突破 → ScrollView 内のホーム全体が中央寄せ/シフトして両端クリップ**という連鎖で「画面全体がずれる」症状になった。

## Why

固定 minWidth の子は「これ以上縮めない」制約なので、合計が親幅を超えると親が広がる方向に解決される。横スクロールでもクリップでもなく「親を押し広げる」のが既定挙動。

## How to apply

- 固定個数のトグル/チップを1行に敷き詰めるなら **`.frame(maxWidth: .infinity)` で等幅フレックス化**し、行に `.frame(maxWidth: .infinity)` を付けて親幅に収める(minWidth 固定をやめる)
- 可変個数で溢れ得るなら **横 `ScrollView(.horizontal)`** でラップ(atender の DayDetailSheet チップ行はこの方式で溢れない)
- 「モーダル/パネルを開くと画面全体がずれる/見切れる」を見たら、そのパネル内の**固定幅横並び**をまず疑う。原因は開いた要素側にあり、親レイアウトではない
- 関連パターン: [[swiftui-bottomsheet-content-fit-detent]]
