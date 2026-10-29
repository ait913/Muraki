---
title: 合成済みのストア画像から端末を透過で切り出して LP / SNS 画像に使い回す (再撮影しない)
category: pattern
tags: [app-store, screenshot, landing-page, og-image, pillow, webp, mask, marketing]
created: 2026-10-30
project: global
sources:
  - Muraki/projects/atender/.designs/20261030-landing-page-and-social-image.md  # §2・§4-1 (初出)
  - Muraki/projects/atender/.designs/20261029-store-screenshots.md  # 切り出し元の HTML 合成
---

## Context

atender で「LP と SNS 用 16:9 画像を、ストア画像の感じで」と頼まれた。ストア画像 (1320×2868) は HTML + CSS 端末で合成済みだが、素材の端末スクショ (`shots/`) は git 管理外で消えていた。再撮影は seed が平日限定・API とシミュレータが要る。

## What

- 合成元の HTML が端末を**絶対座標の CSS** (幅・left・top・角丸 = 幅 × .17・回転・`box-shadow` の外周リング) で置いているなら、完成 PNG から端末の外形を**計算で**復元できる。PIL で「角丸矩形を 4 倍で描いて LANCZOS 縮小したマスク」を作り、回転端末はマスクを同じ角度・同じ原点で回す (CSS `rotate(-8deg)` = PIL `rotate(+8)`)。ペア構図 (2 枚にまたがる端末) は 2 枚を横に連結してから切る
- マスクの外周は CSS の外周リング (`box-shadow: 0 0 0 5px`) の分だけ広げる (`RING = 5`)。広げないとリングが欠けて端末が細く見える
- 端末に重なる別要素 (円バッジの縁と影) は、**同じ座標に同じ端末を持ち、重なりの無い別スライド**の同じ行で上書きできる (CSS 端末は全スライドで画素が一致する。重なる行がベゼルだけで画面に掛からないことを確認してから)
- 出力は WebP (alpha 付き) で 1 枚 40〜85 KB。原画 0.75 MB × 5 枚を CSS で clip するより 1 桁軽い
- 同じ切り出し物を LP (HTML の見出し + 画像) と SNS 画像 (1920×1080 の HTML を puppeteer で撮影) の両方の素材にし、OG (1200×630) は 1920×1080 の上下 36px を落として `clip.scale = 0.625` で同じ HTML から出す

## Why

- 切り出しなら端末の見た目 (ベゼル・傾き・浮いた端末) がストア画像と 1 px も違わず、「ストアと同じ感じ」が自動で満たされる。再撮影は画面の中身 (日付・出欠) がストア画像とずれる
- 見出しを画像に焼かず HTML で組めるので、検索・読み上げ・レスポンシブが効く
- 構図を 1 つの HTML に保つと、OG と 16:9 で文言・配置が乖離しない

## How to apply

- 切り出し定数は「合成元 HTML の CSS」の写しとして表にし、スクリプトの docstring に出どころを書く。合成元を作り直したら定数を引き直す
- 重なり除去は「差分の bbox」を元画像同士で取って、どの行・列が他要素に汚されているかを先に実測する (`ImageChops.difference(...).getbbox()`)
- 検証は切り出し物の特定画素 (角の alpha 0、重なっていた位置のベゼル色) で書き、パッチを外すと赤になることを 1 回実走する
- 傾いた端末の上半分しか写っていないスライドは単独では使いにくい。連結して「傾いた端末 + 隣の端末」の組でまとめて切ると hero に使える
