---
title: 入力フォームモーダル (BottomSheet/Dialog) の視認性 BP (2026)
category: pattern
project: global
tags: [ui, bottom-sheet, dialog, form, readability, wcag, hierarchy, focus-ring]
created: 2026-05-18
sources:
  - https://www.w3.org/TR/WCAG22/#non-text-contrast
  - https://www.w3.org/WAI/WCAG22/Understanding/focus-appearance-minimum.html
  - https://developer.apple.com/design/human-interface-guidelines/layout
  - https://developer.apple.com/design/human-interface-guidelines/lists-and-tables
  - https://m3.material.io/components/text-fields/guidelines
  - https://m3.material.io/components/text-fields/specs
  - https://material-web.dev/components/text-field/
  - https://m3.material.io/components/bottom-sheets/guidelines
  - https://www.nngroup.com/articles/bottom-sheet/
  - https://www.nngroup.com/articles/form-design-white-space/
  - https://tailwindcss.com/docs/hover-focus-and-other-states
  - https://rsms.me/inter/
---

## Context

Modal / Bottom Sheet 内に入力フォームを置く場面で「文字が見えにくい」「階層が弱い」「フォーカスが分からない」と感じる根因は**たいてい設計トークンの欠陥に集約**される。Atender redesign で実装後に Touri 指摘されたパターンを抽象化。

## What

入力モーダルの視認性は以下 5 軸で決まる。**1 つでも崩れると「見えにくい」体感になる**。

### 1. focus ring の WCAG 1.4.11 適合

- 非テキスト UI の隣接コントラスト **3:1 必須** (WCAG 2.2 / 1.4.11)
- 薄い tint (`emerald-100 #D1FAE5` 等) を ring 色に使うと白背景で 1.05:1 となり**事実上見えない**
- 推奨パターン (Tailwind v4): `focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-<accent>-500`
- 旧 `focus:ring-2 ring-<accent>-500 ring-offset-2` も継続有効

### 2. 視覚階層 (label と value の weight 反転)

label を `font-semibold (600)` 強・value を `400` 弱にすると、「タイトル列だけが目立って入力値が霞む」逆転現象が起きる。

```
label: font-medium (500) / fg-secondary
value: font-medium (500) / fg-primary
```

label は補助・value が主役。Linear / Stripe / Notion の SaaS フォームに共通する規約。

### 3. モーダル内 divider (header と body / section 間)

- header (タイトル + 閉じる) と body の境界に `border-b 1px var(--border-subtle)` を必ず引く
- 複数 section があるフォームでは section ごとに `border-t` or `space-y-6` で区切る
- MD3 Bottom Sheet guidelines は header divider を明示推奨

### 4. padding と高さ (8px grid)

| 要素 | 推奨 |
|---|---|
| input 高さ | min-h-12 (48px) |
| input 横 padding | px-4 (16px) |
| label と input の gap | gap-2 (8px) |
| sheet 外周 padding | px-5 (20px) |
| section 間 spacing | space-y-5 (20px) |
| header height | min-h-14 (56px) |

iOS HIG (Layout) と MD3 (Text Field 56dp) のクロス。

### 5. backdrop blur と sheet 内 text の分離

- backdrop (overlay) に blur をかけるのは OK
- sheet 自体は **不透明** (`bg-elevated` = #FFFFFF) で blur をかけない
- 両者を混同して sheet にも transparency + blur を入れると text が霞む (Glassmorphism 罠)

## Why

WCAG 1.4.11 (3:1) の非テキストコントラストが守られないと、focus が見えない・border が消える・状態フィードバックが伝わらない。視認性低下を「色を派手にする」「ダーク mode 追加」で解決しようとすると本質を外す。**正しいのは focus ring 色・weight 階層・divider・padding の 4 つを揃えること**。

label weight 反転は SaaS フォーム調査で頻出する罠。「label を強く見せたい」気持ちで semibold にすると、ユーザーは「入力欄が空っぽに見える」現象に陥る。

## How to apply

新規 modal/sheet を設計する時のチェック:

- [ ] focus ring は accent-500 (3:1 確認済み) で outline 2px + offset 2px
- [ ] label は medium (500) + fg-secondary、value は medium (500) + fg-primary
- [ ] header と body の間に divider (border-b border-subtle)
- [ ] sheet 外周 padding は 20px (px-5)、section 間 20px (space-y-5)
- [ ] input min-h-12 / px-4
- [ ] sheet 自体は不透明 (background は elevated)
- [ ] action footer は sticky 下端 + border-t + safe-area-inset-bottom

逆に**やってはいけない**:

- focus ring を *-100 系の薄い tint で済ます
- label を semibold (600+) で強く・value を regular (400) で弱くする
- header と body をベタで連結する (divider なし)
- input を min-h-10 (40px) 以下にする (タップターゲット未達)
- sheet 自体に backdrop-filter: blur を適用する
