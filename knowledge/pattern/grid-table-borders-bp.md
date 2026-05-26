---
title: グリッド・テーブル罫線 BP (時間割/カレンダー/データ表示)
category: pattern
project: global
tags: [ui, grid, table, calendar, timetable, border, readability]
created: 2026-05-18
sources:
  - https://material.io/blog/google-calendar-redesign
  - https://www.notion.so/help/tables
  - https://www.notion.so/calendar
  - https://flexibits.com/fantastical
  - https://penmark.jp/guide/
  - https://www.w3.org/TR/WCAG22/#non-text-contrast
  - https://developer.mozilla.org/en-US/docs/Web/CSS/color-mix
---

## Context

時間割・カレンダー・テーブル系 UI で「セルがバラバラに見える」「表として認識されない」体感が出るのは、罫線設計が以下のどちらかに偏った時:

- **個別セルに border を付ける方式** (`gap-1` + 各セル `rounded-md border`): セルが島になり表として連結しない
- **罫線一切なし方式**: 列幅が広いと隣接セルが分離不能

正解は **コンテナ側で罫線を 1 本ずつ描く**。

## What

### 罫線の引き方

- **横線主・縦線最小** (Google Calendar / Notion Calendar / Apple Calendar 共通則)
- 横線: 各行の境界に `border-b 1px var(--border-subtle)` (= #E7E5E0 / Slate-200 系)
- 縦線: 時刻ラベル列と本体の境界のみ。本体内の日付間は描かない or 極薄
- グリッド自体は上左 border を描き、各セルが右下 border を持つことで重複なく完成

### CSS (Grid container 側で罫線を描く)

```css
.grid {
  display: grid;
  gap: 0;
  border-top: 1px solid var(--border-subtle);
  border-left: 1px solid var(--border-subtle);
  border-radius: var(--radius-md);
  overflow: hidden;  /* radius を効かせる */
}
.cell {
  border-right: 1px solid var(--border-subtle);
  border-bottom: 1px solid var(--border-subtle);
}
```

### イベントブロック (時間割の授業 / カレンダーの予定)

- 背景: course/category color の **10-12% tint** (色当て塗り)
  - 動的に `color-mix(in srgb, var(--course-color) 12%, white)` で実装
  - 純色 (100%) を背景にすると上に乗る文字が読めない
- 左 border: 4px solid course-color (Google Calendar / Outlook / Notion Calendar 流の category 表示)
- 文字色: ベース text-primary (常に黒系)
- 連続コマは CSS Grid `grid-row: span N` で 1 ブロック化、内部分割線を消す

### 行ラベル列 (時間割なら時限ラベル)

- 背景: bg-muted (#F7F7F5) で本体と差別化
- フォント: font-semibold (600) で時限番号、その下に時刻を text-[10px] text-tertiary で
- center 揃え、min-width 56px

### 空セル

- dashed border は使わない (薄すぎて存在感がない & WCAG 1.4.11 で 3:1 未達のことが多い)
- 案 A: 背景同色 (#FFF) + hover で `bg-muted`
- 案 B: `+` アイコンを `text-tertiary opacity-0 hover:opacity-60` でアフォーダンス

## Why

- 罫線を**個別セル**に付けると「セル + gap」で表が分断され、心理的に表として認知されない (proximity 法則)
- 「横線主・縦線最小」が現代カレンダーの定石なのは、時刻の連続性 (縦軸) より時刻境界 (横軸) の方が認知優先度が高いため
- イベントブロックの背景に純色を使うと文字が読めない・category 識別性も下がる。tint 10-12% は文字 12:1 以上を維持しつつ category 認識を成立させる sweet spot

## How to apply

時間割・カレンダー・テーブル UI を作る時のチェック:

- [ ] gap-0 で罫線方式 (gap-* + 個別 border 方式は採用しない)
- [ ] コンテナに上左 border、セルに右下 border (重複しない設計)
- [ ] 罫線色は border-subtle (#E7E5E0 系) で 1px
- [ ] 横線主・縦線は時刻ラベル境のみ
- [ ] 行ラベル列に背景 tint + font-semibold
- [ ] イベントブロック背景は color-mix で 10-12% tint
- [ ] 左 4px の category accent border
- [ ] 連続イベントは grid-row span で 1 ブロック化
- [ ] 空セルは dashed を避け、hover 起動方式
