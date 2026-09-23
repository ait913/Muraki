---
title: 判定軸 → 視覚チャンネルの割当 — nullable な軸はシルエットに乗せず「外せる」チャンネルに置く
category: pattern
project: bloom
tags: [character-design, mascot, gpt-image-1, shape-language, nullable, image-generation]
created: 2026-09-22
sources:
  - Muraki/projects/bloom/.designs/20260922-character-16types.md
  - Muraki/projects/bloom/.knowledge/research-character-design-system.md
  - Muraki/projects/bloom/server/internal/domain/character.go
---

## Context

N 個の二値軸 (MBTI 型の 2^N タイプ) に画像生成でキャラを与えるとき、どの軸をどの視覚チャンネル (体型 / 色 / 小物 / ポーズ) に割るかで「型が変わったときに絵がどう変わるか」が決まる。bloom の月次キャラ (4 軸 16 体) で採った判断。

## What

1. **チャンネルは遠目で効く順に序列を持つ**: 体型・シルエット > 色味 > 小物 > ポーズ・目。
2. **軸の重要度 (命名で主語になる軸) を強いチャンネルへ** — ただし、
3. **計算不能 (`nil` / `-`) になり得る軸は、体型に乗せない。** 消えても個体の同一性が残る「外せる」チャンネル (小物なし / 中立ポーズ) に置く。
4. 差分は「1 軸 = 1 チャンネル」の 1:1 にし、脚・衣装など余分な差分源を style block で禁止する。1 軸変わると絵の 1 要素だけ変わる = 「変化がコンテンツ」になる。
5. 色は既存 UI パレットと**彩度と材質**で分離する (UI 色がフラット S≥57% なら、キャラは金属グラデ S≤45%)。色相の隣接は許容する。

## Why

- nullable な軸を体型に乗せると、欠測月に別キャラになり「固定しない」が「同一性が無い」に転ぶ。
- Researcher の「nullable は 1 軸だけ」は実装 (`CharType`) を読むと 2 軸だった。**割当を決める前に判定関数の `nil` 経路を全部数える**。
- 軸 ↔ 絵を 1:1 にしておくと、根拠行 (実測値) と絵の要素が対応し「判定根拠を見せる」が絵でも成立する。

## How to apply

- 割当表を「軸 / nullable / 序列 / チャンネル / 遠目での強さ」の 5 列で書き、nullable=yes の行が「体型」に入っていたら組み直す。
- `-` の見た目 (小物なし・中立ポーズ) を 1 行で先に決め、その変種を今回生成するかは別裁定にする (3^k × 2^(N-k) 体に膨らむ)。
- プロンプトは「共通 style block (固定) + 差分 block (チャンネルごとに 1 文) + consistency 文」の 3 層。再生成は外れたチャンネルの文だけ強める。
