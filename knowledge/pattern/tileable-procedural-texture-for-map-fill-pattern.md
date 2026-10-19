---
title: "地図の fill-pattern 用に継ぎ目の無いテクスチャを端末で手続き生成する (トーラス上の周期ノイズ)"
category: pattern
project: bloom
tags: [maplibre, fill-pattern, procedural, noise, domain-warp, tileable, flutter, isolate]
created: 2026-10-11
sources:
  - "bloom .designs/20261011-map-fill-variants.md §5-1 (フルイド / マーブル / 放射円盤)"
  - "Architect の scratchpad 試作 (Dart AOT、Mac で 480px フルイド 約 80ms / マーブル 約 40ms、768px で 190 / 90〜140ms。2×2 に並べて継ぎ目なしを目視、隣接差の比 0.7〜1.5)"
---

## Context

MapLibre の `fill-pattern` は画像をタイル座標に固定して繰り返す。模様 (液体の渦・墨流し) を地図のポリゴンに敷くには、端と端がつながる (tileable) 画像が要る。画像編集ソフトの素材でなく、メンバー色ごとに端末で生成したい。

## What

- **周期 P の格子値ノイズ** (格子値 P×P を種付き乱数で作り、座標を `mod P` で引く) を、octave k で周期 `base << k` にして重ねた fBm を「単位トーラス」(u, v ∈ [0,1) を格子座標 `u·P` に) で評価すると、u と u+1 で同じ値になる
- **ドメインワープ** (`f(u + a·g(u,v), v + b·h(u,v))`) は g, h も周期 1 なら周期性を壊さない。定数オフセット (+0.3) も同じ
- 帯 (`(f·n) mod 1`)、櫛 (`floor(u·tines)`) も **n・tines が整数**なら周期 1
- 櫛の向きを列ごとに反転させる羽根模様は、変位 `λ/(d+λ)` が列の境目で 0 にならず縦の継ぎ目が出る → `λ/(d+λ) − λ/(0.5+λ)` で境目を 0 にする
- 継ぎ目の機械検証: 右端列↔左端列の隣接差が、内部の全隣接列の差の平均の 2 倍以下

## Why

- Dart 純関数にすると決定的 (同じ引数 → 同じバイト) で、`flutter test` からピクセルを直接検証できる。FragmentShader は速いがテスト環境の Impeller 有無に結果が依存する
- `Isolate.run` + `package:image` の `encodePng` で UI isolate を止めない

## How to apply

- 画像サイズは px = pt × dpr (iOS の `addImage` は画面倍率で登録 — `library/maplibre-gl-flutter-0.26-quirks.md` #1)。パターンはタイルのアトラスにも積まれるので「枚数 × 大きさ」を抑える (Bloom は 160pt = 3x で 480px、1 枚 0.9MB)
- `removeImage` が無いので画像名は固定して上書き (quirks #7)、`addImage` は timeout 付き (quirks #6)
