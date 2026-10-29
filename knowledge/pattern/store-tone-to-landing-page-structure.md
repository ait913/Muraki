---
title: ストア画像のトーンを LP に展開するときは「スライド 1:1」でなく LP の定石の節で組み、端末は台で下端を切る
category: pattern
tags: [landing-page, app-store, layout, static-site, lazy-loading, puppeteer, marketing]
created: 2026-10-30
project: global
sources:
  - Muraki/projects/atender/.designs/20261030-landing-page-v2-layout.md  # v2 (本パターンの初出)
  - Muraki/projects/atender/.designs/20261030-landing-page-and-social-image.md  # v1 (スライド 1:1、却下)
  - Muraki/knowledge/pattern/store-composite-phone-cutout-for-lp-and-social.md  # 素材の切り出し
---

## Context

atender の LP v1 はストア画像 5 枚を節に 1:1 で写した (小見出し + 大見出し + 端末 + 図形の繰り返し)。Touri の FB は「雰囲気はこれでいいが、ストア画像を重ねただけ。ページとして作って」。v2 で雰囲気 (色・書体・マーカー・図形・キャラ) を保ったまま構成だけを組み直した。

## What

- **節の型**: Hero → 共感 (困りごと 3 つ) → 使い方 (3 ステップ) → 機能 (交互 2 カラム × N、見出しにストアのコピー) → 対人機能の色帯 → 機能一覧 → FAQ → 最終 CTA → フッター。ストアのコピーは機能行の見出しと Hero・帯にだけ使い、新しいキャッチは作らない (共感・手順・FAQ・CTA の誘導文だけ書き足す)
- **雰囲気を残す場所を絞る**: 散らし図形は Hero と色帯の 2 か所だけ。全節に撒くと v1 の「スライドの連続」に戻る
- **端末の置き方**: ストアから切り出したベゼル付き端末 (下端が切れた素材と全身の素材が混在) は、角丸の台 (`aspect-ratio: 5/4; overflow: hidden`、マーカー色の 14% tint) の中に上 padding から幅 48% で置き、**台の下端で切る**。全身の端末も同じ幅で置けば下が台の外に出て、混在しても見え方が揃う。画面だけの切り出しを新たに作る必要がない
- **見出しの段**: ストアのコピー (大見出し) を機能行の h3 にするときは見た目を h2 と同じ段にする (節の主役)。h2 のサイズは「最長の h2 の字数 × size × (1 + letter-spacing)」が 320px 幅の中身 (280px) に収まる値から決める (atender: 9 字で 28px)
- **lazy loading と検査スクリプト**: Hero 以外を `loading="lazy"` にすると、`networkidle0` 後に `img.complete && naturalWidth > 0` で検査する既存スクリプトは必ず落ちる (画面外の lazy 画像は未読込で `complete === false`。`fullPage` のスクショを撮っても false のまま)。検査の前に「400px 刻みでスクロール → 先頭に戻す → `Promise.all(images.map(i => i.decode().catch(() => {})))`」を入れる。壊れた画像は decode が reject → `complete && naturalWidth` で拾える (負のコントロールで確認済み)

## Why

- LP の読み手はストアの読み手と違い、アプリをまだ知らない。スライドは「1 枚 1 メッセージ」を横にめくる前提で、縦に積むと同じ型の反復になり流れが無い。困りごと → 手順 → 画面 → 迷いの解消 → 入手、の順は読み手の疑問の順
- 台で切る置き方はスクショの上 2/3 (要点が集まる側) を見せ、下の空白 (スクショの余白) を隠せる
- lazy の落とし穴は「設計で `loading` を足した」ことが別ファイルの検査スクリプトの前提を壊す型で、HTML だけ見ていると気付かない

## How to apply

- ストア画像・スライド素材から LP を作るときは、まず上の節の型で IA 表 (節・役割・根拠) を書き、素材を「どの節の何に使うか」に割り振る。素材の枚数から節を作らない
- 画像に `loading="lazy"` を足す設計では、同じリポジトリの画像検査 (puppeteer の `complete` 判定・Lighthouse 系) を grep し、スクロール段を設計 doc に書く
- headless Chrome の `--screenshot --window-size=375,…` はウィンドウ幅の下限 (約 500px) で右が切れる。スマホ幅は puppeteer の `setViewport` で撮る
