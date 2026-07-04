---
title: 設計docの例示値がformula/正典と矛盾しうる — Reviewerは例を鵜呑みにしない
category: gotcha
project: atender
tags: [reviewer, design-doc, day-convention, test-oracle]
created: 2026-07-01
sources:
  - .designs/20260701-ios-port-phase-b-home.md §挙動仕様 T-1
  - apps/web/src/lib/dayConvention.ts
---

## Context

Atender iOS Phase B の Reviewer テスト生成中、`DayConvention.resolveDisplayDays` の
期待値を設計 §T-1 の**例示 prose** から取ったら実装と食い違った。

設計 T-1 の記述:
- formula: `jsToDisplay(js) = ((js + 6) % 7) + 1`
- 例示 prose: `meetings:[dow=5(金→display6)]`

この2つは矛盾する。formula に dow=5 を入れると `((5+6)%7)+1 = 5` (金=display5)。
prose の「金→display6」は誤り (土=display6 と取り違えた doc typo)。Web の
`jsDowToDisplay((jsDow+6)%7)+1` も formula 側と一致 → **formula/正典が正**。

## What

設計docは同一項目に「formula (定義)」と「例示 (期待値)」の両方を載せることがあり、
**例示の方に計算ミスが混入する**ことがある。Reviewer が例示値をそのまま期待値に
コピーすると、実装が正しくてもテストが赤くなる (偽陽性の RED)。

## Why

- 例示は人間が手計算で書くため、境界 (曜日変換の日/土 off-by-one 等) でズレやすい。
- formula・正典 (Web 実装) は機械的に正しい確率が高い。
- 「テストが赤 = 実装バグ」と即断すると、実際は doc typo なのに Developer を無駄に往復させる。

## How to apply

- Reviewer: 期待値は **formula/正典 (Web) から自分で計算**して導く。設計の例示 prose は
  「意図の参考」に留め、値そのものはコピーしない。formula と例示が食い違ったら formula 優先。
- 赤が出たら (a) 実装出力 (b) formula 手計算 (c) 例示 prose の三者を突き合わせる。
  実装==formula≠prose なら **実装 GREEN + doc typo** と判定し、Architect に例示修正を促す。
- Architect: 変換系 (曜日・時刻・index base) は例示に「js0→display値」の全対応表を
  formula 出力で載せると typo が減る。
