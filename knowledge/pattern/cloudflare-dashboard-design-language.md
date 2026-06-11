---
title: Cloudflare dashboard の視覚デザイン言語 (token 抽出 + Tailwind v4 移植案)
category: pattern
tags: [design, ui, cloudflare, dashboard, design-token, tailwind-v4, dark-mode, dense-ui]
created: 2026-06-08
project: global
sources:
  - https://github.com/cloudflare/cf-ui
  - https://unpkg.com/cf-style-const@3.3.0/lib/variables.js
  - https://color.cloudflare.design/
  - https://github.com/cloudflare/color
  - https://blog.cloudflare.com/dark-mode/
  - https://medium.com/cloudflare-blog/thinking-about-color-bfa1696782ec
---

## Context

家計簿アプリ等で「Cloudflare dashboard 風」の高密度・実務的な UI を作りたい場面。CF dashboard は **デスクトップ高密度 + 左サイドバー** 型。本パターンは CF の視覚言語を **design token** に落とし、モバイル/デスクトップ両対応で移植できる形にまとめる。aisaba.net 系の視覚言語 ([[pattern/aisaba-design-language]]) とは**真逆**の方向 (後述「差分」) なので、どちらの語彙で組むか明示してから使う。

## What

### 出典の信頼度 (確認済 / 推測の区別)

- **確定 (一次情報)**: CF の color system は「各 hue = 明度順 10 段階スケール」「dark mode は `reverse()` で明度反転 (hue/彩度は保持)」「dark 背景は純黒でなく `#1D1D1D` 系のオフブラック (純黒は too harsh)」「WCAG AA 4.5:1 を基準」。CF blog (dark-mode / thinking-about-color) + color.cloudflare.design で確認。
- **確定 (一次ソース)**: 下記カラースケール・spacing・fontSizes 等の具体値は **`cf-style-const@3.3.0`** (cf-ui の token パッケージ、unpkg で実体確認) の値。
- **注意**: `cf-ui` 自体は **2021-08 に GitHub archive 済 (unmaintained)**。現行 dash.cloudflare.com は内部モノレポ (公開停止) で運用。よって下記は「CF が公開した最後の公式 token セット」であり、現行 dash の実値と細部は異なりうる。**視覚言語の骨格として転用する分には十分**だが「現行 dash の CSS 変数そのもの」ではない点に注意。
- **推測**: サイドバー幅の px、アクティブ状態の左バー等の現行 dash レイアウト数値は記事/観察ベースで一次トークンなし → 下記で「推測」と明記。

### 1. カラーパレット (cf-style-const v3.3.0 実値)

各 hue は **index 0 (最暗) → 9 (最明) の 10 段階**。dark mode はこの配列を反転利用するのが CF 流。

```
gray   : 0 #1d1f20  1 #36393a  2 #4e5255  3 #62676a  4 #72777b  5 #92979b  6 #b7bbbd  7 #d5d7d8  8 #eaebeb  9 #f7f7f8
orange : 0 #341a04  1 #5b2c06  2 #813f09  3 #a24f0b  4 #b6590d  5 #e06d10  6 #f4a15d  7 #f8c296  8 #fbdbc1  9 #fdf1e7
gold   : 0 #2c1c02  1 #573905  2 #744c06  3 #8e5c07  4 #a26a09  5 #c7820a  6 #f4a929  7 #f8cd81  8 #fbe2b6  9 #fdf3e2
red    : 0 #430c15  1 #711423  2 #a01c32  3 #bf223c  4 #da304c  5 #e35f75  6 #ec93a2  7 #f3bac3  8 #f9dce1  9 #fcf0f2
green  : 0 #0f2417  1 #1c422b  2 #285d3d  3 #31724b  4 #398557  5 #46a46c  6 #79c698  7 #b0ddc2  8 #d8eee1  9 #eff8f3
cyan   : 0 #0c2427  1 #164249  2 #1d5962  3 #26727e  4 #2b818e  5 #35a0b1  6 #66c3d1  7 #a5dce4  8 #d0edf1  9 #e9f7f9
blue   : 0 #0c2231  1 #163d57  2 #1f567a  3 #276d9b  4 #2c7cb0  5 #479ad1  6 #7cb7de  7 #add2eb  8 #d6e9f5  9 #ebf4fa
indigo : 0 #181e34  1 #2c365e  2 #404e88  3 #5062aa  4 #6373b6  5 #8794c7  6 #a5aed5  7 #c8cde5  8 #e0e3f0  9 #f1f3f8
violet : 0 #2d1832  1 #502b5a  2 #753f83  3 #8e4c9e  4 #9f5bb0  5 #b683c3  6 #c9a2d2  7 #dbc1e1  8 #ebddee  9 #f7f1f8
```

**ブランド orange**: 一般に公称される Cloudflare Orange は **`#F6821F`** (ロゴ)。token 上は `cfOrange = #f28021`、UI アクセント用 `colorOrange = #ff7900` (= `orange[6]` 相当の named `tangerine #FF7900`)。**実装では `#F6821F` 系をプライマリアクセントに据えれば CF らしさが出る** (微差。厳密一致が要るならロゴ kit を参照)。

**semantic 色** (cf-style-const themeColors、light 基準):
- info `#00a9eb` (≈ blue[5]) / success `#68970f` (≈ green[5]) / warning `#fca520` (≈ gold[6]) / error `#ff3100` (≈ red[4])
- ※ これらは token の semantic 別名。スケールに揃えるなら `blue[5] #479ad1 / green[5] #46a46c / gold[6] #f4a929 / red[4] #da304c` を使う方が体系的。

**light モードの面色** (token + dark-mode 記事):
- page bg `gray[8] #eaebeb`〜`#e6e6e6` (colorMainBackground) / card・surface `white #fff` / border `gray[7] #d5d7d8` 〜 `#666 (colorGrayBorder)` / 本文 text `gray[1] #36393a`系 (≈ darken 0.8 white) / muted text `gray[4] #72777b`。
- overlay (modal 背景) `rgba(0,0,0,.7)`。

**dark モードの面色** (dark-mode 記事 + reverse 原則):
- page bg `#1D1D1D` (純黒回避) / card・surface は 1〜2 段明るいグレー (`gray[1] #36393a` 付近) / text は反転で `gray[8〜9]` 側 / アクセント orange/blue は明度反転で明るめの段 (orange[5〜6], blue[5〜6]) を使う。具体 token は公開停止のため**スケール reverse で生成する**のが CF 流儀。

### 2. タイポグラフィ (cf-style-const v3.3.0)

- font-family (token): `"Open Sans", Helvetica, Arial, sans-serif`。※ 現行 dash の観察では **Inter** 系 (`Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, ...`) に寄っている (推測)。**新規実装は Inter 推奨** (CF の現行トーンに近く、Tailwind/Google Fonts で扱いやすい)。
- monospace: `SFMono-Regular, Menlo, Monaco, Consolas, monospace` (推測・観察ベース)。
- **fontSizes スケール (px)**: `[10, 12, 14, 16, 20, 24, 32, 48, 64, 80]`。ダッシュ本文 base は **14px**、caption 12px、見出し 20/24/32。
- base fontSize token: `15px` / input `13px`。
- **weight**: light 300 / normal 400 / semibold 600 / bold 700。
- **lineHeights**: solid 1 / title 1.25 / copy 1.5。本文は 1.5、見出し/データは 1.25。

### 3. レイアウト

- **左サイドバー** (現行 dash, 推測): 幅 ≈ 240–260px、折りたたみ ≈ 48–64px。階層は アカウント → ドメイン/プロダクト → 設定の 2〜3 段。アクティブ項目は左端の数 px アクセントバー + 背景の僅かな塗り (一次トークンなし→推測)。
- **トップバー** (推測): 高さ ≈ 64px。左にアカウント/ドメイン切替・breadcrumb、右に検索・通知・プロフィール。
- **コンテンツ**: 白カードを縦に積む。カード間 gap は spacing scale の 16/32。ページ内は max-width で頭打ちにせずワイドに広げる (高密度志向)。

### 4. コンポーネント (cf-style-const + 観察)

- **borderRadius (token)**: グローバル **`2px`** (CF はかなり角丸が小さい = キリッとした実務感)。カードは 4–8px まで許容 (観察)。pill/badge は full (9999px)。
- **boxShadow (token)**: `0 0 20px 0 rgba(136,136,136,0.50)` (modal/popover 級)。カードは軽い shadow か border のみ (観察)。
- **button**: primary = orange 塗り (`#F6821F`/`#ff7900`) + 白文字、radius 2–4px。secondary = white + `1px solid gray[7]`。danger = red[3〜4] 塗り。ghost = 透明 + hover で gray[9] 背景。padding 縦8 横16 目安。
- **input**: `1px solid gray[7]`、radius 2–4px、focus で blue[4〜5] の border + 細い ring。inputHeight token `2.26667rem` (≈36px)、inputFontSize 13px。
- **badge/pill (status)**: full radius、薄い背景 (semantic hue の段9) + 濃い文字 (段3〜4)。例 success = green[9] 背景 + green[3] 文字。
- **table**: 行は border-bottom `1px gray[8]` で区切り、hover 行は gray[9] 背景。高密度 (行高 36–44px 目安)。
- **toast/notification**: card + 左に semantic 色バー。
- **modal**: overlay `rgba(0,0,0,.7)` + 白カード + 大きめ shadow。

### 5. 密度・スペーシング

- **space スケール (px)**: `[0, 4, 8, 16, 32, 64, 128, 256]` (4 基点)。
- CF dash の高密度は「小 radius (2px) + 細 border + 控えめ shadow + 14px base + 行高を詰める」で作る。塗りでなく**罫線と余白の縮小**で密度を出す ([[pattern/grid-table-borders-bp]] / [[pattern/mobile-density-tighten-token-pass]] と整合)。

### 6. データ可視化

- 折れ線/棒は **hue スケールから採色** (主系列 = blue[5] or orange[6])。グリッド線は `gray[8]` の極薄、軸/凡例ラベルは `gray[4]`。背景は透明 (カード白に乗せる)。
- 増減の意味色: 増/プラス = green[5]、減/マイナス = red[4]。残高推移は単色折れ線 + 0 基準線を gray で。カテゴリ別集計は hue スケールを 1 段おきに割当てると色被りしにくい。

### 7. インタラクション

- transition は短く (≈150ms ease)。hover は背景を 1 段明るく/暗く (gray スケール 1 段)。
- **focus-visible**: blue 系の 2px ring または border 強調 (CF は青フォーカス)。
- active は更にもう 1 段濃く。

## Why

CF dashboard の「明度順 10 段階 × hue」モデルは、(1) 色選択を hue + 明度の 2 軸に縮約でき、(2) `reverse()` だけで dark mode が出る、(3) WCAG コントラストが段の位置で予測できる (前半5段は白文字 OK、後半5段は黒文字 OK)、という設計合理性がある。小 radius・細 border・控えめ shadow は「データを主役にする実務ツール」のトーンで、装飾を足さず密度を上げる。

## How to apply

### aisaba 言語との差分 (どちらで組むか先に決める)

| 観点 | aisaba ([[pattern/aisaba-design-language]]) | Cloudflare dashboard (本書) |
|---|---|---|
| 基調 | ダーク + 余白広め + 中央寄せ | ライト主体 + 高密度 + ワイド |
| アクセント色 | なし (下線のみ) | orange を明確に使う + semantic 色フル |
| 区切り | 線/枠を使わず余白 | 罫線・border・カードで区切る |
| 用途 | コンテンツ/ポートフォリオ | 操作的ダッシュボード/データ表示 |

→ **家計簿のようなデータ操作アプリは CF 言語が適合**。aisaba トーンは持ち込まない (混ぜると密度が崩れる)。

### Tailwind v4 `@theme` 移植案 (CSS-first)

```css
@theme {
  /* gray (neutral) */
  --color-gray-0:#1d1f20; --color-gray-1:#36393a; --color-gray-2:#4e5255;
  --color-gray-3:#62676a; --color-gray-4:#72777b; --color-gray-5:#92979b;
  --color-gray-6:#b7bbbd; --color-gray-7:#d5d7d8; --color-gray-8:#eaebeb; --color-gray-9:#f7f7f8;
  /* brand orange (アクセント) */
  --color-brand:#f6821f; --color-brand-hover:#e06d10; /* orange[5] */
  /* hue (必要分だけ) */
  --color-blue-4:#2c7cb0; --color-blue-5:#479ad1; --color-blue-9:#ebf4fa;
  --color-green-3:#31724b; --color-green-5:#46a46c; --color-green-9:#eff8f3;
  --color-red-3:#a01c32; --color-red-4:#da304c; --color-red-9:#fcf0f2;
  --color-gold-5:#c7820a; --color-gold-6:#f4a929; --color-gold-9:#fdf3e2;
  /* semantic (light) */
  --color-info:#479ad1; --color-success:#46a46c; --color-warning:#f4a929; --color-error:#da304c;
  /* surfaces (light) */
  --color-bg:#eaebeb; --color-surface:#ffffff; --color-border:#d5d7d8;
  --color-text:#36393a; --color-text-muted:#72777b;
  /* type */
  --font-sans: Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  --text-xs:12px; --text-sm:14px; --text-base:14px; --text-lg:16px;
  --text-xl:20px; --text-2xl:24px; --text-3xl:32px;
  /* radius / spacing は Tailwind 既定の 4 基点に合致。radius は小さめ運用 */
  --radius-sm:2px; --radius-md:4px; --radius-lg:8px;
}
/* dark: reverse 原則で surface を作る */
[data-theme="dark"] {
  --color-bg:#1d1d1d; --color-surface:#36393a; --color-border:#4e5255;
  --color-text:#eaebeb; --color-text-muted:#92979b;
  --color-brand:#f4a15d; /* orange を明度反転で明るい段に */
}
```

- dark/light/auto の切替は [[pattern/theme-auto-resolve-data-theme-matchmedia]] の `data-theme` 常設 + matchMedia 方式に乗せる。
- **モバイル ⇄ デスクトップ transposable**: token は共通。レイアウトだけ分岐 — モバイルは bottom tab 維持 ([[pattern/mobile-first-bottom-tab]])、デスクトップ (≥768px) で左サイドバー 240px + 高密度カード。視覚 token (色/radius/border/density) は両方に同じ値を適用するだけで CF トーンになる。
- 密度は [[pattern/mobile-density-tighten-token-pass]]、罫線は [[pattern/grid-table-borders-bp]]、フォームモーダルは [[pattern/form-modal-readability-bp]] と併用。
- **厳密に CF 現行 dash の token を取りたい場合**: cf-style-const は 2021 版なので、dash.cloudflare.com を実機 inspect して `--cf-color-*` 等の現行 CSS 変数を採取する (本書値は骨格として十分だが現行実値ではない)。
