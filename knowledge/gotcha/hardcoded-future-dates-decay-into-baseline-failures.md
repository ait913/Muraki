---
title: テストのハードコード「近未来日付」は数日で腐り、ベースライン失敗の山に化ける
category: gotcha
project: atender
tags: [testing, vitest, date, baseline, known-failures]
created: 2026-07-29
sources:
  - "atender apps/api/tests/personal-calendar-share.test.ts (commit 2d6fece, 2026-07-23)"
  - "atender apps/api/src/services/personalCalendarShare.service.ts:100-105"
---

## Context

atender の `projectShare` は投影範囲を **`today().startOfDay` 〜 +3ヶ月**で取る (設計 `20260723-calendar-eventkit-sync-and-redesign.md:230` の仕様どおり)。
テスト `personal-calendar-share.test.ts` は 2026-07-23 に書かれ、当時「近未来」だった `2026-07-25` / `2026-07-26` を**リテラルで**埋めていた。

## What

**2026-07-26 (= 執筆の 3 日後) から 5 件、2026-07-27 から 6 件が自動的に落ち始めた。**
失敗メッセージは `expected [] to have a length of 1` で、**投影ロジックのバグに見える**。実際は実装も設計も正しく、テストの日付が過去に滑っただけ。

実測 (2026-07-29): 日付を +1ヶ月ずらしたコピーを走らせると **9/9 PASS**。境界も逐語確認 —
`date = 2026-07-29 (今日)` は PASS、`2026-07-28 (昨日)` は FAIL。`date >= today().startOfDay` そのもの。

## Why

- `today()` アンカーのウィンドウ (「今日から N ヶ月」「直近 M 日」) を持つ機能では、**テストの絶対日付とプロダクトの相対窓が時間とともにすれ違う**
- レビュー時点では GREEN なので **reviewer も CI も検出できない**。マージ後に静かに腐る
- 腐った失敗は「ベースライン失敗の山」に混ざり、**本物のバグを隠す**土壌になる (CLAUDE.md「ベースライン失敗の台帳」が存在する理由そのもの)
- ★ 設計 doc に書かれた**テスト仕様の例示日付も同じ罠**。atender の `20260729-personal-calendar-rebuild.md` §P (P4=7/23-24, P5=7/27) はもう過去日で、逐語実装すると**生まれた瞬間に落ちる**

## How to apply

- `today()` / `new Date()` 起点の窓を持つ機能のテストでは、**日付を実行時に計算する** (`todayJst().add(3,'day')` 等)。リテラルの `2026-07-25` を書かない
- 過去/未来の境界を検証したい時こそ相対で書く: 「今日−1日 = 除外」「今日+89日 = 含む」「今日+91日 = 除外」
- 設計 doc に例示日付を書くときは「今日+2日」のような**相対表記**にする。絶対日付を書くなら「実装時は相対に置き換えること」と明記する
- 既存の失敗を分類するとき、`expected [] to have a length of 1` 系は**まず日付を未来にずらして再実行**する。1 分で「実装バグ / テスト陳腐化」が確定する
