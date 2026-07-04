---
title: moneylog (ceez7 家計簿) のデザイン言語 — すりガラス + ぼかしグラデ blob + grid-rows 伸縮
category: pattern
project: global
tags: [design, ui, moneylog, ceez7, glassmorphism, mobile-first, animation, grid-template-rows, kinketsu-taisaku]
created: 2026-06-11
sources:
  - https://app.ceez7.com/moneylog/ (ライブ実機、ai.t_913、2026-06-11 実測)
  - https://dl.ceez7.com/style/ceez72/scss/style.css (p-ml__* 実 CSS、93KB)
  - /Users/touri/Desktop/ceez7 bin/ceez7/app/moneylog/ (HTML/JS/SCSS ローカル)
---

## Context

Touri 本人が作った家計簿 moneylog の UI を後継アプリ (金欠対策 / kinketsu-taisaku) で**そのまま踏襲**したい。Touri が「センスがある」と認める自作デザインの design token と UX 原則を一次ソースから抽出。`p-ml__*` の実スタイルは moneylog フォルダ内 (`costom.css` は色変数 288 byte のみ) でなく **ceez7 共通 CSS `ceez72/style.css` (CSSOM クロスオリジンでブロックされるので curl で読む)** にある。

## What — 視覚トークン (実測値)

```
背景      : #fafafa (light) / #181818 (dark)   /* --color_ml_mgray / mdark */
文字      : #1e1e1e (rgb 30,30,30)
フォント   : "Noto Sans JP", "Hiragino Sans", Yu Gothic, 游ゴシック
base 文字  : 12px (密度高め)。残高など主役数値は特大 38px / weight 500
```

**カード = すりガラス (frosted glass)**
- 背景 `rgba(255,255,255,0.75)` (半透明白。背後がうっすら透ける)
- border-radius **15〜25px** (要素で 15 / 18 / 25 を使い分け。hero card は 25)
- 影は極薄ぼかし: `box-shadow: 0 0 8〜10px rgba(20,20,20,0.04〜0.1)` (オフセット 0、ふわっと浮く)
- 入力ボタン等の小カード: radius 15px / padding 10px 15px

**ヒーローのミント発光 = ぼかしグラデ blob を frosted card の背後に置く**
```css
.thumbnail__background        { border-radius:25px; overflow:hidden; display:flex; justify-content:center; align-items:center; }
.thumbnail__background__grad  { position:absolute; top:40px; width:200px; height:90px;
                                filter: blur(40px); opacity:0.7;
                                background: linear-gradient(#03d9ff, #07fa62); } /* cyan→green */
@media (prefers-color-scheme:dark){ .grad { background:linear-gradient(#ff0303,#0747fa); opacity:1; } } /* dark は赤→青 */
```
→ ぼかした blob がガラスカード越しに滲んで「ミントの発光」になる。塗りでなく**光**で色を置く。

## What — モーション (UX の肝。Touri が良いと言う所)

- **どこも `transition: 0.3〜0.5s ease`** (主に 0.3 / 0.4 / 0.5)。瞬間切替を避け常にぬるっと。
- **開閉 (伸縮) = `grid-template-rows: 0fr ↔ 1fr`**。高さを JS で測らないモダン accordion:
  ```css
  .collapsible      { display:grid; grid-template-rows:0fr; overflow:hidden;
                      transition:0.5s grid-template-rows ease; }
  .collapsible.active{ grid-template-rows:1fr; }
  .collapsible > *  { overflow:hidden; }
  ```
  タグ/カテゴリをタップ→該当レコードだけ伸びて出る、の伸縮はこれ。
- **押下フィードバック = `transform: scale(1.02〜1.1)`** (`zoom` / `zoomx2` クラス)。ボタン・アイコンが軽く膨らむ。

## What — レイアウト / UX 原則 (1 画面・モバイル first)

- **タブで割らない完全 1 画面**。開いた瞬間に「月末残高・入力ボタン・レコード」が見える = 必要情報が最初に、目的まで最短。
- **コントロールバー (上部)**: 年月ラベル (タップで 年↔月 モード切替) + `‹ ›` 期間移動 + ⚙ 設定。
- **月モード**: ヒーローカード (月末に残っている残高=大 / 現在残高 / 収支 / 入力する) → 月統合情報 → 収入/支出/移動 → カテゴリ・タグ chip → レコード一覧 (未確定 / 確定 / 概要 bundle にグループ)。
- **タグ/カテゴリ tap → そのタグのみに伸縮フィルタ**。選択ヘッダ (choice) に そのタグの色 + 合計金額 + × を出す。
- **年モード**: 総収支 + **棒グラフ (月別)** + タグ別集計。
- 設定は別画面/シート (バーの ⚙ から)。

## Why

- frosted glass + ぼかし blob は「塗らずに光で色を置く」ので、彩度を上げずに生き生きした印象を作れる (家計簿の数字を邪魔しない)。
- `grid-template-rows 0fr↔1fr` は高さ auto を含む可変コンテンツでも JS 計測なしに滑らかに開閉でき、実装が軽い。
- 1 画面 + コントロールバー mode 切替は、タブ分割より「いま見たい情報への最短距離」を保てる (Touri の中核思想: 開いて即・最短・直感)。

## How to apply (金欠対策で踏襲する時)

- color/radius/shadow/font/blob を上記実測値で再現。Tailwind v4 なら `@theme` + 任意 CSS で frosted card と blur blob を作る (blob は absolute + filter:blur)。
- transition は 0.3〜0.5s ease を既定トークン化。開閉は **必ず grid-rows 方式** (max-height 方式を使わない: 中身可変で破綻するため)。
- bottom tab / sidebar を作らない。ナビは上部コントロールバーの mode 切替に集約。
- dark は `prefers-color-scheme` で blob の色を差し替え (moneylog は赤→青)。

## 後継アプリへの適用設計 (kinketsu-taisaku 2026-06-11、実装トークン化済)

CF 路線却下後、moneylog 忠実再設計で確定したトークン適用パターン (`.designs/20260611-moneylog-faithful-redesign.md`)。流用可:

- **frosted card は `backdrop-filter: blur(8px)` + `rgba(255,255,255,.75)` 面**。card は radius 18px (セクション) / 25px (hero) / 15px (chip)。shadow は `0 0 10px rgba(20,20,20,.06)` のオフセット 0 ふわっと。
- **blob は `.card--hero` を `position:relative; overflow:hidden` にし、中に `<span class="hero-blob">` を absolute (top 40px / 200×90 / blur(40px) / opacity .7 / linear-gradient(cyan,green))**。`.card--hero > * { position:relative; z-index:1 }` で中身を blob の上に乗せる。
- **grid-rows 伸縮 utility**: `.collapsible{display:grid;grid-template-rows:0fr;overflow:hidden;transition:grid-template-rows .4s}` / `.collapsible.active{grid-template-rows:1fr}` / `.collapsible>*{overflow:hidden;min-height:0}`。タグ chip フィルタの choice header もレコード bundle 展開もこれ一つで賄う。
- **dark は `data-theme` を使わず `@media (prefers-color-scheme:dark){ :root{...} }` で CSS 変数を上書き** (Tailwind v4 `@theme` は `:root` に出すので `@media` 内 `:root` 再宣言で勝てる)。blob を赤→青に差し替えるだけ。**手動テーマ 3 択トグル (useTheme/data-theme/localStorage) は moneylog 質感には過剰** — OS 追従単純方式で消す方が忠実。
- **1 カラム中央**: `.shell{max-width:520px;margin:0 auto}`。デスクトップでも同じ幅を中央に置くだけ。横を埋めない (埋めるとダッシュボード化して質感が壊れる = CF 路線の再来)。
- **ナビは bottom tab/sidebar でなく ControlBar (年月ラベル tap で月⇄年 mode / ‹› 期間移動 / ⚙)** に集約。mode は画面内 useState 切替でルート遷移しない。4 ルートを 2 ルート (`/` 統合 Home + `/settings`) に畳める。
- **残高は HeroCard に特大 38px/weight500 で 1 つ**。CF のメトリクスカード 4 枚並べは moneylog 質感に合わない。

## 反例 / やってはいけない (2026-06-11 の失敗から)

- ★ **Cloudflare dashboard 風の高密度テーブル + 左サイドバー + 4 タブ**にしたら Touri に「センスがない」と却下された。moneylog は**柔らかいガラス質感・1 画面・伸縮アニメ**であり、CF の硬質・高密度・タブ分割とは真逆。**外部の有名 UI を持ち込む前に、まず参照元 (moneylog) の design token と UX を一次ソースで研究する**こと。
- データ操作アプリ=高密度テーブル、と短絡しない。Touri の家計簿は「必要情報が最初に出る親しみUI」が正。
