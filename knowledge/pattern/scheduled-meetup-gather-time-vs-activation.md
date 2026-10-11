---
title: 「立てたら即起動」の集合に予定時刻を足すとき — 起動時刻と集合時刻を別列にし、終了条件を表で全部仕分ける
category: pattern
tags: [state-machine, scheduling, auto-end, migration, flutter, cupertino-picker]
created: 2026-10-10
project: global
sources:
  - Muraki/projects/bloom/.designs/20261010-beacon-gather-time-and-comment.md
---

## Context
bloom のビーコン (作成即 active・位置共有開始) に「30分後 / 1時間後 / カスタム」の集合時刻を足す設計。既存の `starts_at` は起動時刻として上限・集計の窓・延長の上限・live 判定の起点に使われていた。

## What
- 集合時刻は起動時刻 (`starts_at`) に混ぜず**別列** (`gather_at`) にする。起動時刻に未来値を入れると、上限 (+6h)・recruiting の拾い上げ・集計の窓が全部意味を変える。
- 新列は NULL 可で backfill しない。読み出しを `COALESCE(gather_at, GREATEST(created_at, starts_at))`、上限の起点を `GREATEST(created_at, starts_at, gather_at)` (Postgres の GREATEST は NULL を無視) にすると、旧行・seed・SQL で行を作るテストが無改修で旧値になる。
- 自動終了条件を「集合前に止める / 起点を集合時刻にずらす / そのまま」の表で全数仕分けする。bloom では (a) 全員離脱 15 分・(d) 承諾者 ≤1 が集合前に誤発火し、(c) 作成 +6h が 6 時間後の集合をちょうど切る。「今すぐ」(集合 = 作成時刻) で停止区間が空になる形にすると既存挙動と回帰しない。
- 到着の定時判定・夜型など「時刻を基準にした集計」も起動時刻を見ていたら、基準を集合時刻に直す (案X では起動 = 作成なので全員が遅刻寄りに歪む)。
- 相対プリセット (30分後) は**押した瞬間に絶対時刻へ固定**し、確定ボタンのラベルにその時刻を出して同じ値を送る。時計で刻んで確定時に再計算すると 5 分境界をまたいだ瞬間に表示と送信が食い違う。
- Flutter の時刻ホイール: `CupertinoDatePicker` の time モードは日付またぎの範囲を min/max で絞れない (doc: 同じ日付前提)。localization delegate の無いアプリでは dateAndTime モードが `Today` / `AM` の英語表示。「今 +5 分〜+6 時間、5 分刻み」は `CupertinoPicker` 1 列にスロットを並べ、日付が変われば `明日 HH:mm` と書く方が範囲が正確。
- 選択肢 4 つの横並びで「同じ選択肢を再タップして開き直す」必要があるなら `CupertinoSlidingSegmentedControl` は使えない (選択中のセグメントの再タップで `onValueChanged` が来ない)。

## Why
既存の時刻列は複数の機能の「起点」を兼ねていることが多く、意味を足すと別機能の境界が黙って動く。列を分けて、終了・集計の各条件をどちらの時刻で見るかを表にすれば、影響範囲が grep 可能な数に収まる。

## How to apply
「即時のものに予定時刻を足す」要望では、(1) 既存の時刻列を `grep` して起点として使っている箇所 (上限・live 判定・延長・集計の窓・基準時刻) を全部挙げ、(2) 予定時刻用の列を別に足し、(3) 各箇所を「止める / ずらす / そのまま」で表にして設計 doc に書く。危険窓 (予定時刻ちょうど・予定時刻 −30 秒・上限ちょうど) の標本時刻を挙動仕様に入れる。
