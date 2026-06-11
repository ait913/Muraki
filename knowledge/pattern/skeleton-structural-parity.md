---
title: スケルトンは実UIの外殻クラスを複製し決定的パターンで埋める
category: pattern
tags: [skeleton, loading, react, tailwind, testability]
created: 2026-06-11
project: atender
sources:
  - projects/atender/.designs/20260611-ui-polish.md
---

## Context

atender のスケルトン (CalendarMonth/Timetable 等) が実 UI と padding/gap/セル形状 (aspect-square vs min-h-24) で乖離し、ロード完了時にレイアウトシフトと違和感を生んでいた。UI polish 設計で全面見直し。

## What

スケルトン設計の 3 原則:

1. **外殻クラス複製**: 実コンポーネントのコンテナ class (`rounded-2xl bg-bg-elevated p-2 shadow-card`, grid 定義, `min-h-*`) をそのままコピーする。寸法をスケルトン側で再発明しない
2. **静的部分は実物を出す**: ロード中でもデータ不要な要素 (曜日ヘッダの「月火水…」、local state だけで動く PeriodNav/タブ) はスケルトンでなく実物を render する。ロード前後の見た目差が最小になる
3. **プレースホルダ個数は index ベースの決定的パターン** (`[2,1,0][index % 3]` 等)。乱数は禁止 — Reviewer が「aria-hidden 要素がちょうど N 個」とテストできる

## Why

- スケルトンの目的は「完成形の予告」。構造が違うと逆に認知負荷とシフトを生む
- 全セル敷き詰め (時間割で全コマ skeleton) は実物 (大半が空セル) と密度が違いすぎる。一部セルだけ埋める方が忠実
- 決定的パターンなら設計docに要素数を確定値で書け、実装を見ないテスト生成が成立する

## How to apply

- スケルトン新規作成時、まず実コンポーネントのルート〜グリッド定義の className を読み、そのまま転記する
- viewMode 等で実 UI が切り替わる画面は、スケルトンも同じ分岐で出し分ける (月グリッド固定スケルトンを週/日ビューに使い回さない)
- 設計doc には「aria-hidden 総数」「構造を示す class (min-h-24 等) の個数」を確定値で明記する
