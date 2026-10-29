---
title: App Store スクショの HTML パイプラインを別アプリへ移植する (寸法換算・文字数上限・素材の撮り方)
category: pattern
tags: [app-store, screenshots, html-render, puppeteer, xcuitest, status-bar, layout]
created: 2026-10-29
project: global
sources:
  - projects/atender/.designs/20261029-store-screenshots.md
  - projects/bloom/mocks/store/ (移植元)
---

## Context
Bloom の `mocks/store/` (1290×2796、COPY + CSS + puppeteer-core) を atender (1320×2868、白基調) に移植する設計で決めたこと。

## What
1. **寸法の換算は数値置換。`transform: scale` は使わない**。6.9" の受理サイズ同士 (1290×2796 / 1320×2868) は縦横比が違う (×1.0233 / ×1.0258)。横 (位置・幅・フォント・角丸) は横倍率、縦 (top・影の y) は縦倍率で丸めた整数を CSS に直書きする。端末モックの `aspect-ratio` は素材の実寸比に合わせる (cover で切らない)
2. **見出しの文字数上限はレイアウトから導出して doc に表で持つ**。1 行の上限 = 見出し幅 ÷ (font-size × (1 + letter-spacing))。バッジ・マスコットが見出し 2 行目の y 範囲と重なるなら、2 行目だけ上限が下がる (右端 = left + 文字幅 × n < バッジ左端)。文言を差し替える人がこの表だけで判定できる
3. **傾いた大端末 (ペア構図) は画面の上半分しか写らない**。重要な部品が画面下端にある画面 (出欠ボタン等) は傾いた端末に置かず、全体が縮小で写る小さい直立端末に回す
4. **素材は XCUITest で辿って XCUIScreen で撮る**。`simctl io screenshot` は遷移 (タブ・スクロール・シート) を操作できない。`simctl status_bar override` は XCUIScreen の撮影にも効く。`continueAfterFailure = false` にして誤った画面を素材にしない
5. **render は「フォント未読込・素材欠け」で PNG を書かずに exit 1**。HTML 側で `dataset.fontLoaded` と `dataset.missing` (decode に失敗した img) を出し、render が見る。Bloom は fontLoaded をログに出すだけで、欠けた画像を黙って出せた
6. **配色は CSS 変数 + `?theme=`、文言は `?copy=a|b`** で、承認ゲートに 4 通りを並べて出せる。出力ディレクトリ名に組み合わせを入れる (`out/a-light/`)
7. **ストア用デモ seed は既存の UI テスト用 seed と分ける** (別ユーザー・別 token)。平日ガード (今日の授業が無いとホームの出欠が写らない)・本番 DB ガードを書き込み前に置き、`now` を引数で受けて計算結果 (「あと N 回」) を vitest で固定する

## Why
移植元の CSS を倍率一律で縮尺すると歪むか余白が出る。文字数上限を書かずに文言だけ渡すと、承認後の文言修正でバッジと重なる。画像の生成は目視が最終ゲートなので、自動検証は「形 (寸法・ファイル・文言の一致)」と「seed が作る数字」に絞るのが割に合う。

## How to apply
別アプリ・別寸法でストア画像を作るとき、移植元の CSS 値を表 (元値 / 換算値) にして doc に載せ、§2 の文字数表と §5 の exit 規則を最初から入れる。素材の画面ごとに「画面のどこに価値の部品があるか」を見て、ペア構図の傾いた端末に載せる画面を選ぶ。
