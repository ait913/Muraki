---
title: XCUITest は起動直後の最初の 1〜2 タップを失う (offset のせいだと誤診する)
category: gotcha
project: atender
tags: [ios, xcuitest, test-harness, false-red, negative-control, reviewer]
created: 2026-07-30
sources:
  - "atender build 16 P4 Reviewer 検証 (2026-07-30) — 設計 #H3 (chip 非タッチ化)"
  - "実測: iPhone 16 / iOS 18.2 Simulator, デモ bearer token 起動"
model-era: opus-4.8
---

## Context

「予定 chip の真上をタップしても chip がタップを食わず、日別シートが開く」(#H3) を
`cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()` で検証した。
→ **シートが開かず RED**。「chip がタップを食っている = 実装バグ」に見えた。

## What

同じセルに **offset を変えて連続タップ**する診断を書いたら、真因が出た:

| 撃った順 | dy | 開いた |
|---|---|---|
| 1 | 0.8 | ✗ |
| 2 | 0.2 | ✗ |
| 3 | 0.8 | ✓ |
| 4 | 0.2 | ✓ |
| 5 | 0.15 | ✓ |

**offset 依存ではなく順序依存**。起動 + データ読込直後の最初の 1〜2 タップが失われる
(レイアウトが確定する前に撃っているため)。`waitForExistence` は要素の**存在**しか待たず、
「タップを受け付ける状態」は保証しない。

## Why

- 最初の一撃で判定する UI テストは、**実装が正しくても RED になる** (偽 RED)
- 逆に「retry でいつか通る」だけにすると、**当たり判定バグを見逃す** (chip が食っていても別の場所で通れば緑)

## How to apply

**対照 (control) と本題 (subject) の 2 段で書く。**

1. 対照: 明らかに通るべき場所 (日番号の帯 dy=0.2) を **retry 付き**でタップし、シートが開くまで粘る
   → 「セルが押せる」ことの証明 + **空振りの消費**
2. 閉じてから、本題 (chip 帯 dy=0.85) を **1 回だけ**タップして判定

対照が通って subject が落ちたときにだけ「chip がタップを食っている」と言える。
retry の回数を subject に持たせないのが要点 (持たせると判別力が消える)。

**ついでに**: SwiftUI の月カレンダー日セルのラベルは `"15、プログラミング演習"` のような複合になる。
`app.buttons["15"]` の完全一致では掴めない (`label == "15" OR label BEGINSWITH "15、"` で撃つ)。
かつ**グリッド先頭行には前月の同じ番号**が居る (7 月のグリッドに 6/29, 6/30) ので、
`"30"` を狙うと**当月外の 6/30** を掴む。狙いたい日は chip のラベル (`label CONTAINS "バイト"`) で絞る。
