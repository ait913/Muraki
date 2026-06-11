---
title: CSS Grid で一部だけ明示配置すると自動配置アイテムがズレて流れる
category: gotcha
project: global
tags: [css-grid, grid-placement, layout, react]
created: 2026-06-02
sources:
  - Muraki/projects/atender 時間割グリッド崩れ修正 (2026-06-02)
  - apps/web/src/components/timetable/TimetableView.tsx
---

## Context

CSS Grid で背景セル (罫線・ヘッダ・ラベル) を素直に並べ (自動配置)、その上に一部のアイテム (イベントブロック等) だけ `gridColumn`/`gridRow` を明示指定して重ねる構成。「明示したやつだけ位置が決まって、残りは順番通り並ぶだろう」と思うと崩れる。

## What

**CSS Grid の配置アルゴリズムは「行・列を明示指定したアイテムを先に配置し、自動配置のアイテムをその後で残った空きセルに流し込む」** (DOM 順ではない)。

結果、明示配置アイテムが占有したセルを自動配置アイテムが避けて流れるため、背景セルが意図しない位置にズレる。実例: 時間割で各イベントだけ `gridRow: n / span k` を付け、限目ラベル/曜日ヘッダ/空セルを自動配置にしていたら、**限目ラベルがグリッド本体 (別の曜日列) に押し出され、行高も崩壊**した。

## Why

明示配置は DOM 順より優先して先にグリッドを占有する。自動配置は「次の空きセル」を左上から探して埋めるので、先に埋まったセルがあるとそれ以降が全部後ろにシフトする。span するアイテムが複数セルを占有すると影響が大きい。

## How to apply

- **混ぜない**: 同一グリッド内では「全アイテム自動配置」か「全アイテム明示配置」のどちらかに統一する。一部だけ明示するなら**残り全部にも明示の gridColumn/gridRow を付ける**。
- 行/列インデックスは **配列 index ベース**で算出する (periodIndex 等の業務的な値が連番でない可能性。`array.indexOf(value) + offset`)。
- 別解: 背景を 1 つのグリッド層、前景 (イベント) を別の絶対配置層に分離する。ただし行高同期が面倒なので、全明示配置の方が単純で堅牢。
- jsdom テストでは `style` 属性の `grid-row`/`grid-column` 生文字列で配置を assert (getComputedStyle/実レイアウトは評価されない)。
- 関連: [[pattern/timetable-consecutive-cell-grid-row-span-coalesce]] — この pattern で grid-row span を導入した結果この罠を踏んだ。span 導入時は背景セルの明示配置とセットで。
