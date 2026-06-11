---
title: モバイル密度を上げる Token 一括パス (font scale + spacing semantic)
category: pattern
project: global
tags: [tailwind, design-tokens, mobile-first, density, timetable]
created: 2026-05-28
sources:
  - Muraki/projects/atender/.designs/20260528-v9.1-density-tighten.md
  - https://cloud.cloudflare.com/dashboard (visual reference)
  - https://timetreeapp.com (visual reference)
---

## Context

モバイル Web アプリで「1 画面に情報を載せたい」要件が来たとき、コンポーネントを 1 個ずつ手で調整する
のではなく **CSS 変数 (Design Token) を 1 ファイルで一括圧縮** することで、全画面の密度を一斉に上げられる。
適用が早く、後で戻すのも簡単。Atender v9.1 で実証。

特に viewport 高さが厳しい iOS (SE 667 / 13 mini 812) で「TopBar + BottomTab + section gap」が
viewport の 25-30% を占有しているケースで効果絶大。

## What

3 軸の token を一斉に圧縮する:

### 1. Typography scale を Minor Third (1.20) に落とす

```css
/* Major Third 1.25 (情報量低い、見出し主役) */
--text-base: 16px;
--text-xl: 25px;
--text-5xl: 61px;

/* Minor Third 1.20 + base=14 (情報量高い、表が主役) */
--text-base: 14px;
--text-xl: 20px;
--text-5xl: 44px;
```

加えて `html { font-size: 14px }` を入れると Tailwind v4 の rem ベース `text-*` `gap-*` `h-*` などが
全部 14/16 倍に縮む (Tailwind 設定なしで全体ダウンサイズ可能)。

### 2. Spacing semantic を一段降格

```css
/* before */
--page-px-mobile: 20px;
--card-padding: 20px;
--section-gap-mobile: 32px;
--button-gap: 12px;

/* after */
--page-px-mobile: 12px;
--card-padding: 12px;
--section-gap-mobile: 16px;
--button-gap: 8px;
```

8pt grid を維持しつつ「規定値を 1 段下げる」運用。

### 3. Chrome (TopBar / BottomTab) の高さを iOS HIG min まで詰める

```css
/* iOS Human Interface Guidelines: tab bar 49pt, touch target 44pt min */
--tab-bar-height: 64px;  /* content 48 + safe-area 余白 */
--topbar-height-mobile: 48px;  /* 56→48 でも brand+icon は収まる */
```

### 4. viewport 残 height を CSS calc で grid に丸投げ

```css
--self-tt-chrome: 352px;  /* TopBar + main pt + ContextChips + ViewModeTabs + Picker + main pb + BottomTab */
```

```tsx
<div style={{
  height: "calc(100dvh - var(--self-tt-chrome) - env(safe-area-inset-bottom, 0px))",
  display: "grid",
  gridTemplateRows: "28px repeat(5, minmax(0, 1fr))",
}}>
```

各セルは `minmax(0, 1fr)` で均等割。`min-height: 320px` を保険に。

## Why

- **一括圧縮の効率**: 各コンポーネント内 hardcode は最後の手当のみ。token 5-6 行の変更で全画面が縮む
- **戻しやすい**: 「やっぱり戻したい」と言われたら token 1 ファイルで元に戻る
- **HIG / WCAG クリア維持**: tap target 44pt min、日本語 body 13px min は崩さない設計範囲で
- **TimeTree / Cloudflare Dashboard の見た目**: 罫線最小 + 太字ヘッダ + 細 font + 一覧表主役、を CSS だけで再現

## How to apply

1. デザイン doc に「Token 改定表」を必ず置く (旧 → 新)
2. `styles.css` を最初にパッチ。実装者が触る順は token → layout primitive → component
3. component 側は **既存ハードコード `text-[N]px` を尊重** (px 直値は html font-size 影響を受けない)
4. 共通化できる視覚パターン (例: `EventTile` = tint bg + 左 pill + title + subtitle) は **`density` prop で
   compact/comfortable を切り分け** 一個に統合
5. 「1 画面表示」要件は `--<screen>-chrome` token で chrome 合計を変数化、`calc(100dvh - var(--*-chrome))` で grid に当てる
6. テストは **CSS regex (fs.readFileSync + match)** で token 値を assert + RTL で各 component の hardcode class を assert
7. Reviewer の最終視覚回帰は chrome-devtools MCP で mobile 375×667 viewport screenshot
