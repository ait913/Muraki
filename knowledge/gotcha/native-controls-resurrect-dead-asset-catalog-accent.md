---
title: 標準部品への回帰が asset catalog の「死に資産」を蘇らせる (リブランド取り残しの掘り起こし)
category: gotcha
project: atender
tags: [ios, swiftui, asset-catalog, accentcolor, tabview, rebrand, dead-code, migration]
created: 2026-07-17
sources:
  - projects/atender/.designs/20260717-ios-ui-revamp.md (§4.1 / §9.3 / §8.7 #S11-#S12)
  - atender P2 実装で Developer が実測 → Leader が現物確認 → Architect が re-grep + actool 実走 (2026-07-17)
  - atender 7ac596f (2026-07-09「水色(azure)配色へ刷新」) / ad12e5a (足場コミット)
---

## Context

atender の iOS UI 刷新で、自前 `BottomTabBar` を native `TabView` に置換した (Liquid Glass 対応)。
設計は「IA も symbol も label も変えない、`.tabItem` に渡すだけ」= 見た目の退行は無いはずだった。

## What

**native 化した瞬間、ブランド accent が azure `#1E96E6` → orange `#F97316` に退行した。**

- 自前 `BottomTabBar` は `Color.accent500` (azure) を**明示描画**していた (`.fill(Color.accent500)`)
- **native 部品はそれを引かない。asset catalog の `AccentColor` を引く**
  (`ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor`)
- その実体は **`#F97316` = 9 日前のリブランド `7ac596f` が `Color+Atender.swift` から削除したのと同じ hex**。
  `git log -- Assets.xcassets/AccentColor.colorset` の最終更新は**足場コミットのまま = 一度も移行されていない**

**なぜ 9 日間も露呈しなかったか: この asset を読む消費者が 1 つも無かったから。**
`Color.accentColor` / `Color("AccentColor")` の参照は grep で 0 件 (`.accent` のヒットは全て `Color.accent` = コード側トークンのエイリアス)。
→ **native `TabView` / nav bar が「最初の消費者」になった。**

影響範囲は tab bar だけではない。**nav bar の back chevron / toolbar も同じ asset を引く**ので、
`TabView` にだけ `.tint` を当てると **タブは azure・back は orange** という中途半端な状態になる。

## Why

**死に資産は「消費者が 0 だから」腐ったまま生き延びる。**
リブランドは「アプリの色を変える」作業として実行されるが、実際に触るのは *その時点で参照されているもの* だけ。
参照 0 の定義 (asset catalog / build setting / テーマ plist) は grep にもレビューにも引っかからず、
**「まだ誰も見ていない値」として過去のブランドを保存し続ける**。

**標準部品への回帰は、その最初の消費者を作る行為**であり、構造的に **過去の移行の取り残しを掘り起こす**。
自前部品は属性を*明示的に*渡していた。標準部品は同じ属性を*暗黙に*どこかから引く。
その「どこか」の実値を誰も検証していないと、置換 = 暗黙の供給元の初お披露目になる。

## How to apply

**1. 自前 → 標準の置換では、明示→暗黙の対応表を作って供給元の実値を実測する**

| 自前が明示的に渡していた属性 | 標準が暗黙に引く先 | 実値を見たか |
|---|---|---|
| accent 色 | `AccentColor` asset (`ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`) | ← ここが腐っていた |
| フォント | `UIAppFonts` / system text style | |
| 余白・高さ | system default / safe area | |

`git log -- <asset path>` で「**一度も移行されていない**」ことまで見える。最終更新が足場コミットなら赤信号。

**2. 直し方は `.tint` を撒く (漏れを追う) でなく asset を正す (単一の定義を直す)**

`.tint` は漏れの追いかけっこになる: tab bar を直すと nav bar が残り、nav bar を直すと**次に足す target (widget 等) が新しい root なので再発**する。
asset は「このアプリの accent」の単一の定義。そこを直せば全 native 部品に一度に効く。
(cf. 「相手側の設定で回避する案」と「自分側を頑健にする案」が並んだら後者)

**3. これは「色の変更」でなく「是正」— スコープ規約と衝突しない論法**

設計が「色の値を変えない」と定めていても、この修正は通せる:
- **ブランド決定は既に下りている** (`7ac596f`)。asset はその決定から取り残された残骸で、保持している値は*同じコミットが削除した当の hex*。新しい色を決める行為ではない
- **既存のピクセルが 1 つも変わらない** (消費者 0 なので)。値が効き始めるのは native 部品を入れた瞬間から

**4. 不変条件をテストで固定する — ただし hex をベタ書きしない**

```swift
// asset とコードの accent が「同じ色である」ことを検証する (hex は書かない)
let light = UITraitCollection(userInterfaceStyle: .light)
let asset = UIColor(named: "AccentColor")!.resolvedColor(with: light)
let token = UIColor(Color.accent500).resolvedColor(with: light)
// RGBA 成分を accuracy 0.001 で比較。dark trait でも同様
```

- **`#1E96E6` と書くと「asset が特定の hex である」の検証になり、次のリブランドでまた置き去りになる。**
  検証すべきは「**2 つの正典が一致していること**」— これがあれば `7ac596f` の当日に落ちていた
- **負の対照を必ず添える**: asset の light 解決値と dark 解決値が**互いに異なる**こと。
  無いと「両 trait が同じ値」でも緑になり vacuous (実際、退行時の asset は light/dark とも同一の orange だった)

**5. 「orange を全部消す」に走らない — トークン系統を分ける**

同じ `#F97316` がコード側に 4 箇所 + フィクスチャに残っていたが、それらは **accent ではなく「科目・メンバー色」= 別系統の現役の値**で、テストが assert していた。
**hex 文字列で grep して一括置換すると別系統を壊す。** 是正対象は asset 1 ファイルだけ。

**6. `AccentColor.colorset` は 8-bit hex 表記で書くとコード側 hex と対応が読める** (actool + assetutil で実証済)

```json
"components" : { "alpha" : "1.000", "blue" : "0xE6", "green" : "0x96", "red" : "0x1E" }
```
float (`0.118`) に丸めると `UIColor(hex: 0x1E96E6)` との対応が diff で読めなくなる。
`xcrun actool <cat> --compile <out> --platform iphonesimulator --minimum-deployment-target 17.0` →
`xcrun assetutil --info <out>/Assets.car` で焼かれた実値を確認できる。
