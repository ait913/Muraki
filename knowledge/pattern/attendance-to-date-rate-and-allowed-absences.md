---
title: 出席率の3指標分解 — 「今日まで実績 / 楽観射影 / あとN回休める」標準計算パターン
category: pattern
project: global
tags: [attendance, stats, denominator, projection, occurrence, ux]
created: 2026-06-11
sources:
  - Atender .designs/20260611-semester-redesign.md
  - Atender apps/api/src/services/attendanceStats.ts
---

## Context

出欠管理アプリで「学期全体の予定回数」を分母にすると、学期序盤は未来分が分母に入って率が不当に低く出る。ユーザーが本当に知りたいのは (1) 今日までの実績率と (2) あと何回休めるか。

## What

occurrence (実日付に展開された授業実体) を 3 クラスに分けて集計する:

- **fixed**: 記録あり → ルール重み (num, den)。REDUCE_DENOMINATOR/CANCELLED は den=0、SEPARATE は両方除外
- **floating past**: date <= today かつ記録なし (= 未記録)
- **floating future**: date > today かつ記録なし。休講日は全クラスから除外

3 指標:

1. **今日まで率** = 過去 fixed の Σnum / Σden。**未記録は分母に入れない** (記録忘れで率が暴落すると数字への信頼を失う)。未記録は件数チップで別出しして記録を促す
2. **楽観射影** projectedNum/Den = fixed 全期間 + floating 全部を出席仮定 (num1/den1)
3. **あと N 回休める** = `floor(projectedNum − r × projectedDen + 1e-9)` (r = 必要出席率)。ABSENT が num −1 / den ±0 だから一次式で解ける。負値はそのまま返し UI が「下回る見込み」表示

## Why

- 「今日まで」は実施日が要るので申告回数 (totalSessions) ベースでは原理的に計算不能。occurrence ベース一択
- 未記録の扱いを率 (除外) と射影 (出席仮定) で分けるのがミソ: 射影は「未来は出席する」仮定と対称で一貫し、率は確定情報のみで正直
- 必要出席率は Int % (例 70) で持つ。Float 0.7 は floor 境界 (ちょうど 70% で N が 1 ズレる) を二進誤差で狂わせる。epsilon 1e-9 併用
- 全体値の「あと N 回」は科目別 floor の和ではなく**射影を合算してから floor** (floor の非線形性)

## How to apply

- HALF_PRESENT 等で分子が 0.5 刻みになっても floor が端数を吸収するので式はそのまま
- 未来日に事前記録があれば fixed 扱い (floating から外す)
- DTO は既存の学期全体率フィールドを壊さず `toDate` / `remainingCount` / `allowedAbsences` を追加する形が安全 (他画面の後方互換)
- UI 分岐: N<0「残り全部出席しても届かない」/ N>=残り回数「全休でも維持」/ それ以外「あと N 回休める」
