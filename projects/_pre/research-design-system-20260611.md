# Research: kinketsu-taisaku DESIGN.md 設計前リサーチ (2026-06-11)

Touri 指摘: margin/padding チグハグ・アイコン不統一・入力モーダルが select でなく moneylog 風ボタンであるべき。
4/8/16 spacing スケールの DESIGN.md を確立し全体を再調整したい。
中核2原則: ①最短到達ルート/IA ②情報優先度づけ+レイヤー化 (font/margin で視覚差別化)。

調査経路: ローカル一次ソース (moneylog HTML/JS/CSS) + Gemini (外部BP) + WebSearch (npm現行性)。

---

## Part A — moneylog 一次ソース抽出 (全て実 CSS 行番号付き / /tmp/ml_style.css 93KB, app_display.html 469行)

### A-1. 入力モーダル radio ボタン群 (record popup) — Touri が「select→ボタン」と言う核心

HTML 構造 (app_display.html 335-376):
```
.p-ml__input__shelf                         <- 1 行 (ラベル + コントロール、横並び)
  .p-ml__input__shelf__label  "確定"
  .p-ml__input__radio                       <- ラジオ群コンテナ (横スクロール)
    <input type=radio id=.. name=ml_rg_paid value=paid>
    <label for=.. class="p-ml__input__radio__label">確定</label>
    <input type=radio .. value=not>
    <label class="p-ml__input__radio__label">未確定</label>
```
カテゴリも同じ radio 群 (JS が `ml_rg_category` に収入/支出/移動を radio 挿入)。**タグだけ現状 select** (`p-ml__input__select`)。

CSS (3185-3214):
```css
.p-ml__input__radio {            /* 群コンテナ */
  max-width: fit-content;
  padding: 10px 10px 10px 5px;
  display: flex; flex-direction: row; flex-wrap: nowrap;
  justify-content: flex-start; gap: 5px;
  overflow-x: auto; scrollbar-width: none;   /* 横スクロール・スクロールバー非表示 */
  cursor: pointer;
}
.p-ml__input__radio__label {     /* 各ボタン (非選択時) */
  width: 80px;
  padding: 10px 15px;
  border-radius: 8px;
  text-align: center;
  flex-shrink: 0;
  box-shadow: 0 0 10px var(--color_c2_shadowl);   /* 浮くガラスボタン。border ではなく shadow */
}
.p-ml__input__radio input:checked + .p-ml__input__radio__label {  /* 選択時 */
  background-color: var(--color_c2_middle1);   /* light: gray 面 / dark: white3 面 */
  color: var(--color_c2_backg);                /* 背景色を文字色に反転 = 反転塗り */
}
```
要点:
- 実 input は CSS で非表示 (label が見た目)。`input:checked + label` で選択表現。
- **非選択 = 透明ガラス + shadow のみ (border なし)**、**選択 = middle1 で塗り潰し + 文字反転**。これが moneylog の選択 UI の質感。
- 横並び・はみ出たら横スクロール (折返しではない、nowrap)。各ボタン width:80px 固定 + gap 5px。
- select も同質感: `padding 10px 15px / margin 5px 10px / radius 8px / shadow 0 0 10px shadowl`。**タグも button 群化するなら radio__label と同スタイルで揃えられる** (選択肢が多ければ横スクロール群、moneylog の radio はまさにそれ)。

### A-2. popup / window / shelf / submit 構造 (全モーダル共通)

```css
.p-ml__container__popup {        /* 全画面オーバーレイ (2350) */
  position: fixed; top: 50px; height: calc(100vh - 50px); width: 100vw;
  backdrop-filter: blur(40px);   /* 背景全体を強ぼかし (overlay 自体) */
  opacity:0; visibility:hidden; transition:0.3s;   /* .active で出現 */
}
.p-ml__container__popup__cd {    /* クリックで閉じる透明レイヤ (2373) */ }
.p-ml__container__popup__index { /* スクロール枠 (2379) */
  max-height: calc(90vh - 50px); margin:10px; overflow:auto;
}
.p-ml__container__window {       /* モーダル本体カード (2388) */
  width: fit-content; max-width: calc(100% - 20px); min-width: 260px;
  padding: 8px 10px 10px 10px;   /* 上8 / 横10 / 下10 (非対称・密) */
  margin: 10px;
  backdrop-filter: blur(40px);
  background-color: var(--color_c2_ui);   /* rgba(255,255,255,.75) すりガラス */
  border-radius: 15px;
}
.p-ml__container__window__title { padding-block-end: 8px; font-size: 14px; text-align:start; }
.p-ml__container__window__container { padding-block-start: 2px; font-size: 14px; }
.p-ml__container__window__index { font-size:12px; padding-block:10px; padding-inline:5px; }  /* alert 本文 */
.p-ml__container__window__status {       /* インライン検証メッセージ枠 (2418) */
  height:0; overflow:hidden; transition:0.3s;   /* .active で height:30px に伸びる */
}
.p-ml__container__window__status__index { font-size:13px; font-weight:500; color: rgb(230,59,122); } /* エラー桃 */
.p-ml__container__window__submit {       /* ボタン行 (2438) */
  padding-block: 15px 5px; display:flex; justify-content:center; gap:15px;
}
.p-ml__container__window__submit__button {  /* キャンセル/確定/削除 (2447) */
  padding: 10px 15px; border-radius: 13px;
  box-shadow: 0 0 10px var(--color_c2_shadowl);   /* ガラスボタン (radio と同質感) */
  transition: 0.3s;
}
.p-ml__container__window__submit__button:hover { box-shadow: 0 0 5px var(--color_c2_shadowl); }
.p-ml__container__window__submit__button.invalid { display:none; }   /* 削除ボタンを新規時隠す */
```

shelf / input 群 (3153-):
```css
.p-ml__input__shelf {       /* 1 入力行 */ min-height:57px; display:flex; flex-direction:row; align-items:center; }
.p-ml__input__shelf__label { min-width:75px; padding-inline:5px 10px; }   /* 左ラベル列 */
.p-ml__input__shelf__setting { min-height:40px; padding-block-start:10px; padding-inline:10px; justify-content:space-between; } /* 設定行は左右両端寄せ */
.p-ml__input__text  { width:400px; max-width:calc(100% - 10px); padding:13px 15px; margin-inline:5px; border-radius:12px; box-shadow:0 0 10px shadowl; font-size:14px; }
.p-ml__input__text:focus { outline:none; }   /* ★ focus ring なし (knowledge form-modal-bp と相反、設計判断要) */
.p-ml__input__date  { padding:10px 15px; margin:5px 10px; border-radius:8px; box-shadow:0 0 10px shadowl; }
.p-ml__input__select{ padding:10px 15px; margin:5px 10px; border-radius:8px; box-shadow:0 0 10px shadowl; }
.p-ml__input__color { margin:5px 10px; border-radius:8px; }
```

category/tag/alert モーダル: 全て同じ window/shelf/submit を使い回す。
- tag popup: カテゴリ radio 群 + color picker + 名前 text + status×2 + submit(キャンセル/確定/削除)。
- category popup: 名前 text のみ + status + submit。
- alert popup: title + index(本文 12px) + submit(キャンセル/OK)。
→ **モーダルは完全に共通コンポーネント化されている** (window + shelf 行 + submit 行)。

### A-3. spacing 実値の棚卸し (★ Touri の 4/8 希望と現実のズレ)

padding/margin/gap 頻度 (上位):
```
10px ×118   5px ×72   15px ×39   8px ×15   20px ×15   7px ×12   3px ×10   12px ×7   30px ×5   2px ×5
```
border-radius 頻度: 15px ×44 / 10 ×11 / 20 ×10 / 8 ×8 / 18 ×6 / 25 ×4 / 13 ×2 / 12 ×1

★★ **判定: moneylog の spacing 体系は 4/8 系ではなく実質 5px 刻み (5/10/15/20/25/30)**。最頻 10/5/15 が 5の倍数。8px は副次 (15回、主に padding-block の 8)。radius は 5刻みでなく 8/10/13/15/18/20/25 と不規則 (ガラス感のための大き目 radius)。
→ Touri の希望「4/8/16」と moneylog の実態「5/10/15/20」は**別グリッド**。設計判断が必要:
  - 案 A (推奨): **8px グリッドに正規化** = 5→4 or 8、10→8、15→16、20→24、25→24、30→32。Tailwind/HIG 標準と整合し margin/padding のチグハグが消える (Touri の主目的に直結)。radius は moneylog 質感維持のため 8/12/16/24 に丸め (ガラスの大 radius は残す)。
  - 案 B: moneylog 5px グリッドを忠実踏襲 (5/10/15/20)。質感は完全一致だが Touri の「4/8/16 にしたい」希望と外れる。
  → **Touri は明示的に 4/8/16 を望んでいる**ので案 A。moneylog 値は「どの semantic にどの段を当てるか」の参考にする (例: 入力行 padding 10→ token space-3=12px、submit gap 15→ space-4=16px)。

### A-4. アイコン (現状 PNG、統一感の欠如要因)

実体: `/moneylog/common/img/*.png` 13種:
back / next / settings / edit / cancel / calendar / list / compress / arrow-up / arrow-down / favicon / service1 / service2。
- 用途: back/next=月送り (control bar)、settings=⚙、edit=入力ボタン、cancel=選択解除/閉じる、list=年表示、compress=bundle折畳、calendar、arrow=並べ替え/展開。
- 表示: control-bar アイコン `30×30px` (.p-ml__control__icon-button、内 img 100%)、入力ボタンアイコン `20×20px`、padding は `.p3/.p7` util (3px/7px) で個別調整。
- 色: 単色 PNG を `.invert { filter: invert(100) }` で light=黒/dark=invert解除(白). → **PNG を CSS filter で色反転して使い回す前提**。1セットを invert で 2 トーン化。
- 動き: `.zoom:hover{scale(1.02)}` / `.zoomx2:hover{scale(1.1)}` で押下膨張。

★ **問題点 (Touri 指摘の「統一感ない」根因)**: PNG はサイズ/stroke/塗りがアイコン毎にバラつきうる + filter:invert は色管理が雑 (任意色不可、accent 着色できない)。
→ **推奨: SVG 単一セット (lucide-react) に全置換**。stroke-width 2 / viewBox 24 で統一。色は currentColor で CSS から自由 (invert ハックを廃止)。Part B-6 参照。

### A-5. タイポ階層 (情報優先度の付け方、実値)

base: `body { font-size:12px }` (密度高)。font-family 日本語 Noto Sans JP系、数値は "Open Sans"。
主要階層 (実 px / weight):
```
38px / 500   月末残高 balanceLast (Open Sans)        <- 最優先・唯一の特大
30px         (一部見出し)
25px / 400   月収支 data__value (Open Sans)          <- 第2階層・大数値
24px / 500   (年モード総計など)
20px / 400-500 カテゴリ別金額 category__header__data / records 区分
16px / 500   セクションタイトル category__header__title / pageDate
15px         レコードラベル・タグ label/value (本文主)
14px / -     モーダル title/container/text/input       <- フォーム標準
13px         キャプション discription / status / 補助
12px         body base / data__title / alert index     <- 最小メタ
```
原則: **数値は Open Sans + 大サイズ + weight 500、ラベル/メタは Noto + 小 + 400**。色でなくサイズ+weight+font-family の3軸で優先度を符号化。最優先 (残高) だけ 38px で隔絶。

色: 文字 `#1e1e1e` 単色基調 (rgb 30,30,30)。エラーのみ桃 `rgb(230,59,122)`。タグ色は丸チップ (16×16 radius8) で表現し文字色は変えない。
→ **色を優先度に使わず、size/weight/font で階層化**。Touri 原則②と完全一致。

---

## Part B — 外部 BP (Gemini + WebSearch、確認/推測区別)

### B-1. spacing システム (確認)
- 8px (or 4px) グリッドが業界標準。要素が画面解像度の倍数に揃い half-pixel ぼけを防ぐ。@2x/@3x で破綻しない。
- スケール: 4/8/12/16/24/32/48/64/96。
- 使い分け: component 内 padding = 12 or 16 / 関連要素 gap = 8 / 別グループ間 = 16 / セクション margin = 16(mobile端) or 24。
- 出典: Material 3 Layout (https://m3.material.io/foundations/layout/understanding-layout/overview), Apple HIG Layout (https://developer.apple.com/design/human-interface-guidelines/layout), Tailwind spacing (https://tailwindcss.com/docs/customizing-spacing)。

### B-2. modular type scale (確認)
- モバイルは Major Third 1.2〜1.25 比が標準 (見出しが画面幅で過大にならない)。
- スケール例: 12(caption)/14(secondary)/16(body)/20(title)/24(headline)/32(display)。
- line-height: body 1.5 / 見出し 1.2。weight: title 600 / body 400。
- 出典: Material 3 Typography (https://m3.material.io/foundations/typography/overview), Apple HIG Typography (https://developer.apple.com/design/human-interface-guidelines/typography)。

### B-3. 視覚階層 (確認 + 一部opinion)
- 優先度は size + color contrast + elevation の組合せで符号化。
- 家計簿の例: 残高=最大font/最太/高コントラスト、レコード=base 16/medium/濃灰、メタ=12-14/regular/muted。
- (opinion) レコード群は border でなく薄灰カード塗りでグループ化しノイズ減。
- 出典: NN/g Visual Hierarchy (https://www.nngroup.com/articles/visual-hierarchy-ux-definition/)。
- ※ moneylog は color を階層に使わず size/weight/font の3軸 (A-5)。moneylog 流の方が「色は意味色だけ」で一貫性高い。Touri 原則と整合する moneylog 流を採用推奨。

### B-4. 選択 UI: segmented/button-group vs dropdown (確認)
- 2-5 択は segmented control (可視ボタン群) が dropdown より速い: 2タップ→1タップ、全選択肢が常時可視で認知負荷減 (Fitts)。
- 推奨: 収入/支出/移動・確定/未確定・日/週/月 = segmented。6+ (カテゴリ20+) のみ dropdown/モーダルピッカー。
- 出典: NN/g Dropdowns (https://www.nngroup.com/articles/drop-down-menus/), Apple HIG Segmented Controls (https://developer.apple.com/design/human-interface-guidelines/segmented-controls)。
- → moneylog の radio 群 (A-1) はまさに segmented。Touri の「select→ボタン」は BP 的に正しい。タグも候補が少なければ button 群、多ければモーダルピッカー化。

### B-5. IA / 最短到達 (確認)
- タスク頻度で配置: "記録追加"=最頻=1タップ (thumb zone)、"設定"=低頻=右上アイコン。
- 最大深さ 3 タップ。主要アクション (追加/保存) は画面下部 thumb zone。
- 出典: NN/g Path Length (https://www.nngroup.com/articles/path-length-usability/)。
- → moneylog は 1 画面 ControlBar mode 切替 (タブ分割しない) で「開いて即・残高/入力/レコードが見える」。記録追加=ヒーロー内「入力する」ボタン1タップ。月/年=年月ラベル tap。タグ閲覧=chip tap で伸縮フィルタ。既に最短。DESIGN.md でこの IA を原則化。

### B-6. アイコンシステム (確認 + npm 現行性)
- 単一 SVG セット (統一 stroke幅/サイズ/viewBox) でないと visual friction。PNG 混在は高DPIでピクセル化 + 任意色着色不可。
- React は component 型ライブラリ推奨 (color/size を prop で操作)。inline component が一般的 (tree-shaking 効く)。
- **lucide-react**: 最新 ~1.17.0 (2026-06 時点・直近13日内 publish)。**default stroke-width 2 / viewBox 0 0 24 24 / fill:none / stroke:currentColor / linecap・linejoin round**。`import { Settings } from 'lucide-react'` → `<Settings size={20} strokeWidth={2} />`。MIT・活発。出典: https://www.npmjs.com/package/lucide-react , https://lucide.dev/guide/packages/lucide-react
- **@phosphor-icons/react**: 最新 2.1.10 (2025-05 publish、直近1年 release なしだが推奨パッケージ・legacy phosphor-react を置換)。fill/thin 等 weight 切替が強み。出典: https://www.npmjs.com/package/@phosphor-icons/react
- → **推奨 lucide-react** (直近メンテ活発・stroke統一・currentColor で moneylog の単色基調+invert廃止に最適)。moneylog の 13 PNG を lucide にマッピング: back→ChevronLeft, next→ChevronRight, settings→Settings, edit→Pencil/Plus, cancel→X, list→Calendar/List, compress→ChevronsDownUp, arrow-up/down→ArrowUp/Down, calendar→Calendar。size は control=20-24, inline=16-20 で 4px grid に揃える。invert ハック廃止、色は currentColor + CSS で light/dark 切替。

---

## 設計への含意 (DESIGN.md へ)

1. ★ **spacing は 8px グリッドに正規化採用** (4/8/12/16/24/32/48)。moneylog の 5/10/15/20 値は semantic 割当の参考に留める (忠実踏襲でなく Touri 希望優先)。チグハグ解消の主目的に直結。token は `--space-1..n` で定義し全 component が token 経由。
2. ★ **radius は moneylog 質感維持で大き目 (chip 8-12 / card 16-18 / hero 24)**。8px grid と独立に質感トークン化。
3. ★ **入力モーダルの select を segmented button 群に置換** (収入/支出/移動・確定/未確定)。moneylog radio スタイル準拠 = 非選択ガラス+shadow / 選択 accent 塗り+文字反転 / 横並び nowrap+横スクロール。タグは少数なら button群、多数ならモーダルピッカー。BP 的にも正 (B-4)。
4. ★ **アイコンを lucide-react SVG 単一セットに全置換** (stroke 2 / viewBox 24 / currentColor)。PNG + invert filter 廃止。サイズは 16/20/24 を 4px grid で統一。「統一感ない」の根本解決。
5. **タイポ階層は moneylog 流 3軸 (size+weight+font-family) で符号化、色は意味色のみ**。残高 32-38/500 を最優先で隔絶、レコード 15-16、メタ 12-13。modular scale 12/14/16/20/24/32(/38) を token 化。
6. **IA は moneylog の 1 画面 + ControlBar mode 切替を原則化** (タブ分割しない)。記録追加 1 タップ、最大深さ浅く。
7. **モーダルは window/shelf/submit の共通コンポーネントとして 1 つに統合** (moneylog が既にそう)。
8. 注意: moneylog の `input:focus{outline:none}` は WCAG focus ring と相反 (knowledge/pattern/form-modal-readability-bp)。DESIGN.md で focus-visible リング (accent-500 3:1) を補う判断を Architect に委ねる。
