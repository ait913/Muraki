---
title: 「承認された初期値」をテストにリテラルで焼くと、その定数を上げた瞬間に赤くなる
category: gotcha
project: atender
tags: [testing, vitest, versioning, baseline, known-failures, boundary]
created: 2026-07-29
sources:
  - "atender apps/api/tests/version.test.ts (#G2/#G3/#G4/#V6)"
  - "atender .designs/20260717-version-management.md §8"
  - "atender apps/api/src/lib/clientVersion.ts (MIN_IOS_BUILD 1 -> 12, build 12 リリース)"
---

## Context

atender の `MIN_IOS_BUILD` は「これ未満の iOS ビルドを 426 で弾く」ポリシー定数。
設計 §8 の検証条項は**すべて相対的な性質**で書かれている:

- #G2 `build > MIN_IOS_BUILD` → 素通し
- #G4 `build === MIN_IOS_BUILD` → 素通し (`<` で弾く、`<=` ではない)
- #G3 `build < MIN_IOS_BUILD` → 426 + `details.minIOSBuild`
- #V6 `/version` の `minIOSBuild` が定数と一致し、1 以上の整数

にもかかわらず生成されたテストは、当時の値 1 を**リテラルで固定**していた:
`"ios/2"` (= MIN+1 のつもり) / `"ios/1"` (= 境界) / `"ios/0"` (= MIN-1) / `expect(MIN_IOS_BUILD).toBe(1)`。
設計 §8 の地の文にあった「`MIN_IOS_BUILD` はテスト時 1」という**環境の説明**を、テストが**仕様として焼き込んで**しまった形。

## What

破壊的変更のリリースで `MIN_IOS_BUILD` を 1 → 12 に上げた瞬間、**4 件が同時に赤くなった** (17 failed → 21 failed)。

- #G2/#G4: `ios/2` `ios/1` が 426 になり「素通し」assert が落ちる
- #G3: `details.minIOSBuild` が 1 でなく 12
- #V6: `expect(MIN_IOS_BUILD).toBe(1)`

**どれも実装バグではない**。実装は設計どおり動いており、テストが陳腐化しただけ。
しかもリリース作業のたびに再発するので、放置すると「ベースライン失敗の山」に定着する。

## Why

- ポリシー定数は**上がることが仕事**。上がらない定数ならテストに焼いてもよいが、上がる定数を焼くのは「変更を禁止する assert」を書いたのと同じ
- レビュー時点では GREEN なので誰も検出できない (時限式ではなく**リリース連動式**の腐り方)
- `expect(MIN_IOS_BUILD).toBe(1)` は「初期値の承認」を守っているつもりで、**実際には設計のどの条項も検証していない**。#V6 の規範は「API の戻り値が定数と一致」であって「定数が 1」ではない
- 姉妹ケース: [[gotcha/hardcoded-future-dates-decay-into-baseline-failures]] (こちらは時間で腐る)。共通の根は「テストが『今の値』のスナップショットをリテラルで持つ」

## How to apply

- **境界テストは定数を import して導出する**。`MIN + 1` / `MIN` / `MIN - 1` を名前付き定数にし、ヘッダ等はビルダ (`iosHeader(build)`) で組む
- 導出が成立する**前提そのものを assert する** (例: `MIN - 1` が正当なヘッダであるために `expect(MIN_IOS_BUILD).toBeGreaterThanOrEqual(1)`)。これで前提が崩れたときに黙って vacuous にならない
- 「承認された初期値」「現在の値は N」のようなテストは書かない。値の妥当性は**別の不変条件**で守る (atender は §9 の `MIN_IOS_BUILD <= project.yml の CFBundleVersion` が本来の安全弁)
- テスト名にも値を書かない (`ios/2 passes through` → `a build greater than MIN_IOS_BUILD passes through`)。値入りの名前は次の bump で嘘になる
- 直したあとは**将来 bump のプローブ**で証明する: 定数と CFBundleVersion を N+1 に一時的に上げて全緑を確認し、cp バックアップから `diff` でバイト復元する
- 相対化しただけでは「緩めたのでは」の疑いが残るので、**変異で境界の拘束を示す**: `<` → `<=` で #G4 だけ赤 / `< MIN` → `< 1` (定数追従の切断) で #G3 だけ赤 / `!==` で #G2 だけ赤 / route の `minIOSBuild` を literal 化で #V6 だけ赤。1 変異 = 1 テストに対応すれば、値の追従でなく性質を見ていることの証明になる
