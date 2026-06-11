---
title: 設計docの導出数値 (個数合計) は生成規則と矛盾しうる — 規則を規範とする
category: gotcha
tags: [design-doc, reviewer, test-generation, arithmetic]
created: 2026-06-11
project: atender
sources: [".designs/20260611-ui-polish.md A10"]
---

## Context

Atender UI小修正のレビューで、設計docが skeleton のプレースホルダ配置を「`(dayIndex + rowIndex) % 3 === 0` のセルだけ Skeleton」という生成規則で定義しつつ、「days=5, rows=5 なら 9 セル / aria-hidden 計 14」と手計算の合計も併記していた。

## What

規則どおり数えると 5×5 の該当セルは **8 個** (合計 13) で、doc 記載の「9 / 14」は誤記だった。実装は規則に正しく従っており、doc の合計値から書いたテストだけが落ちた (13 ≠ 14)。

## Why

設計docに「生成規則」と「人間が暗算した導出値」を両方書くと、暗算ミスで二重仕様が矛盾する。テスト生成側が導出値の方を信じると、実装が正しいのに RED に見える。

## How to apply

- Architect: 個数などの導出値を書くなら、規則から機械的に検算する (列挙して数える)。自信がなければ規則だけ書く
- Reviewer: 導出値と生成規則が両方ある場合、**規則を規範**として自分で再計算し、矛盾したら「実装バグ」でなく「設計の誤記」と判定する (YELLOW 系)
