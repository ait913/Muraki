---
title: aisaba.net 系の視覚デザイン言語
category: pattern
tags: [design, ui, aisaba, dark, minimal, typography]
created: 2026-05-10
project: global
sources:
  - https://aisaba.net
  - https://aisaba.net/about
  - https://aisaba.net/blogs
  - https://aisaba.net/works
  - https://apps.aisaba.net/portfolio_manager
---

## Context

aisaba.net・apps.aisaba.net・portfolio_manager 等、ユーザー (Touri Aida) が運営する複数サイトで一貫した視覚言語が使われている。新規 UI を作る・既存サイトに追加コンポーネントを差し込む際、特に指定がなければこの言語に揃えるのがデフォルト。

## What

### カラーパレット
- 背景: 黒 → 深いネイビー (#000 〜 #0a1830 あたり) の縦グラデ
- テキスト: ほぼ白 (#f0f0f0)
- アクセント色なし。リンクは下線のみで表現
- ボタン・カードに塗りはほぼ使わない

### タイポグラフィ
- 太い sans-serif (Helvetica Neue Bold / Inter Bold / Noto Sans JP Bold 系)
- 大見出しは特大 + 太字 (例: "I'm Touri Aida" がページの主役)
- 本文サイズは控えめ
- リンクは下線のみ (ホバーで僅かに fade 程度)

### レイアウト
- 中央寄せ (max-width 狭め、左右余白広い)
- 縦書き擬似のサイドキャプション (例: "- touri aida based in tokyo/chiba -")
- 装飾 (アイコン・背景・シャドウ) は最小限
- カード型 UI: ContentHeader 画像 (256/1280px) + 太字タイトル + タグ群
- セクション区切りに罫線・枠は使わず、余白で表現

### 情報アーキテクチャ
- About / Works / Blogs の3タブ基本構成
- タグでクロス参照 (`/works/tag/Python`, `/blogs/tag/AI` など)
- 一覧 (カード) → 詳細 の2階層

### マイクロコピー
- 英語タイトル + コロン2つ ("About::", "Works::", "Portfolio::", "Blogs::")
- 日本語混在 OK ("Hi There!" + "はじめまして、とうりです👋")
- 控えめな絵文字 (👋 程度)

## Why

「機能・コンテンツが見えればよく、装飾は邪魔」という思想。ダーク基調 + 余白広めは Web エンジニア界隈で好まれる落ち着いた可読性のため。「::」は名前空間/プログラミング感の演出 (C++/Rust の scope resolution からの引用)。アクセント色を持たないのは、コンテンツ自体を主役に置くため。

## How to apply

- aisaba/appily 系の新規ページ・モーダル・コンポーネントを作る時、まずこの語彙で組む
- 派手な色・アイコン・グラデは入れない (依頼があれば別)
- 太字 + 余白でリズムを作る、線・枠で区切らない
- フォントは Helvetica Neue / Inter / Noto Sans JP で揃える
- リンクは下線・色変えなし、ホバーで僅かに opacity fade
- カードは画像 + タイトル + タグの単純構成、影や境界線は極力なし
- 見出しに「::」を付けてもよい (ユーザーの慣用)
- マーケ語 ("画期的" "シームレス" "革新的") は禁忌 — トーンを壊す
