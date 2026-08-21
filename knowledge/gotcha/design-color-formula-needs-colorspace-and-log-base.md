---
title: 色/強度の数式仕様は「色空間・適用段・対数の底」まで書かないと検証も実装も割れる
category: gotcha
project: bloom
tags: [design-doc, color, heatmap, reviewer, formula]
created: 2026-08-20
sources: [projects/bloom/.designs/20260819-phase0-requirements-ia.md §7, sessions 2026-08-20 P2b review]
---

## Context

bloom R3 §7 のヒートマップ規則「彩度 = 1 − (混ざった人数 − 1)/(グループ人数 − 1) × 0.85、明度・不透明度 = 累積強度の対数」を Reviewer が設計docだけからテストした。

## What

- 「彩度」が HSV か HSL か、**加法混色そのものが生む自然な脱飽和の前か後に適用するのか**が未規定。実装は加法混色の RGB をそのまま出しており、n=4/5 人混合で HSL 彩度 0.059 (式は 0.3625) と大きく割れ、しかも n=4 が n=5 より無彩色になる非単調が出た (補色に近い 4 色の加法和はほぼ灰色になるため)。
- 「対数」も log(x) か log1p(x) かで検証可能な性質が違う: 純 log は倍化増分が一定、log1p は増分が漸増して log2 に収束する。Reviewer が「凹性 (増分減少)」を仮定すると log1p 実装を偽 RED にする。

## Why

数式を 1 行で書くと実装者は「雰囲気が合う」実装 (自然脱飽和まかせ・log1p・clamp) を選び、Reviewer は式を字義どおりテストして割れる。どちらも設計に忠実なつもりになる。

## How to apply

- Architect: 色の式は「HSL の S を式の値に**明示的に設定**する (混色は色相決定のみに使う)」のように**適用段**まで書く。対数は `opacity = a + b·ln(1+x) を [lo, hi] に clamp` の形で底・切片・clamp を定数表に載せる。
- Reviewer: 式仕様が曖昧なら、端点 (n=1 で本人色 / n=N で無彩色) と単調性のような**解釈に依らない性質**と、式そのもののテストを分けて書き、後者の失敗は「実装バグ or 設計の曖昧さ」として帰属を保留する。
