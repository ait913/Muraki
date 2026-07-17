---
title: スクショの byte 一致は「タップが効かなかった」と「ハーネスが辿り着かなかった」を区別しない
category: gotcha
project: atender
tags: [xcuitest, ios, screenshot, test-harness, negative-control, false-red, device-portability]
created: 2026-07-17
sources:
  - atender UI 刷新 P2 の Reviewer 検証 (2026-07-17) — 設計 §10.1-2c
  - projects/atender/.designs/20260717-ios-ui-revamp.md
  - Muraki/knowledge/gotcha/mutation-must-be-proven-to-reach-all-sites.md (同じ「変異が届いたか」の系)
---

## Context

XCUITest の tap は**当たらなくても失敗しない** (ソフトタップ)。`Executed N tests, 0 failures` は
「タップが効いた」を 1 ミリも保証しない。実際 atender の P2 実装ではタブピッカーが**タップ不能に壊れた状態で
`Executed 6 tests, 0 failures`** を返した。

→ 対策として「**タップ前後のスクショが byte-identical なら tap は no-op**」という判定条件が設計に書かれた。
これは正しい発想で、実際に壊れを捕まえた。**が、この指標には第 2 の失敗モードがある。**

## What

**byte-identical は 2 つの全く違う事象を同じ値で返す:**

| 事象 | スクショ | 帰属 |
|---|---|---|
| A. 対象画面に居るが、タップが当たらない (被覆・溢れ) | 一致 | **実装バグ** |
| B. **ハーネスがそもそも対象画面に辿り着いていない** (別画面で撮り続けている) | 一致 | **ハーネスの問題** |

atender では **iPhone SE で B を踏み、A と誤診しかけた**:
- `ScreenshotFlow` は iPhone 16 向けに書かれており、SE では `ルーム` タブの tap が `isHittable` ゲートで落ちて**ホームに留まった**
- 次に `buttons CONTAINS "情報処理科"` が**ホームの ContextChip** (ルーム名のチップ) に誤ヒットして tap
- 結果、`E02-room-detail_ok=true` という名前で**ホームのスクショ**が保存され、続く `時間割` tap は
  **ホーム側の既に選択済みのセグメント**だったので当然 no-op → **byte-identical**
- ファイル名は `_ok=true`、テストは `TEST SUCCEEDED`、指標は「壊れている」と言う。**3 つとも嘘**

## Why

**`_ok=true` が意味するのは「その label の element が存在した」だけで、「正しい画面の正しい element だった」ではない。**
label ベースのクエリ (`buttons["時間割"]` / `CONTAINS "情報処理科"`) は**画面をまたいで衝突する** —
ルーム名は「ルーム一覧のカード」にも「ホームの ContextChip」にも出る。`firstMatch` はどちらを掴むか保証しない。

かつ **UI テストハーネスはデバイス非可搬**。画面寸法が変われば `isHittable` ゲートの結果が変わり、
**フローの分岐が変わって別の画面に着地する**。「同じフローを SE でも走らせる」は設計 doc が書きやすい一文だが、
**ハーネスがその移植性を持っているかは別問題**。

## How to apply

**1. byte-identical を見たら、まず「その画面に居たか」を確かめる。実装を疑うのはその後**

スクショを**実際に目で見る** (ファイル名とテスト結果は嘘をつく)。
`app.navigationBars` のタイトルや、その画面にしか無い accessibilityIdentifier を assert してから撮る。

**2. 帰属は「同じフローを分岐元 (main) で走らせる」で決める**

```
main でも byte-identical  -> ハーネス由来の既存アーティファクト (feature の RED ではない)
main では別ハッシュ        -> feature が壊した (真の RED)
```
atender の SE 一致は **main でも再現** → P2 の回帰ではないと 1 コマンドで確定した。
(`git worktree add <path> --detach <main>` で feature を汚さずに撮れる)

**3. 「タップが効いたか」は byte 差分でなく `isHittable` の方が帰属が綺麗**

byte 差分は「画面が変わったか」しか言わない (= B と混ざる)。
**壊れている側で `isHittable == false` が出る**なら、そちらが直接の指標になる:

```
壊れた実装 (溢れて nav bar に被覆): カレンダー hittable=true / 時間割 hittable=false
直した実装:                        カレンダー hittable=true / 時間割 hittable=true
```
**両方を撮って対にする**のが最良 (byte 差分 = 効果の証明 / `isHittable` = 原因の局在)。

**4. 「浮くべき要素が浮いているか」は frame の一致で見る — ただし空振りに注意**

FAB が `ScrollView` の外にいる (viewport 固定) ことは `element.frame` がスクロール前後で**同一**なら示せる。
**ただしスクロールしていない画面では自明に同一になる (vacuous)。**
→ **先に「コンテンツが実際にスクロールしたか」を別ハッシュで証明してから** frame 一致を主張する。
atender では壊れた側 (ScrollView 無し) が「FAB 不動」を vacuous に満たしており、
**負の対照として使えないことをこの手順で検出した**。

**5. accessibilityIdentifier は「付いている要素の種別」まで確認してから検証条項に書く**

設計 §10.1 は `app.buttons["room-detail-tabs"].isHittable` を要求したが、
`room-detail-tabs` は `buttons` / `otherElements` / `segmentedControls` の**いずれでも解決しなかった** (`exists == false`)。
Picker に付けた identifier はコンテナに載り、XCUITest には**セグメントのラベル** (`カレンダー` / `時間割`) として現れる。
→ **検証条項に element クエリをベタ書きする前に、1 本の使い捨てプローブで `exists` を確かめる。**
