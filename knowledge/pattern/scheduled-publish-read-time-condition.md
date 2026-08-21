---
title: 定時公開は「read 時の時刻条件 + 冪等バッチ」で組む (公開をバッチに依存させない)
category: pattern
project: bloom
tags: [batch, scheduler, coolify, timezone, publish, idempotency]
created: 2026-08-20
sources:
  - Muraki/projects/bloom/.designs/20260820-phase1-tech-foundation.md (§11 SV1/SV3)
  - Muraki/projects/bloom/.knowledge/research-backend-appily.md (Coolify cron 停止バグ coolify#6638)
model-era: fable-5
---

## Context

「毎日 21:00 に全員へ一斉公開」のような定時公開機能。素直に「cron が 21:00 に published フラグを立てる」と組むと、(a) Coolify Scheduled Task には cron が止まる既知バグがある、(b) バッチ失敗 = 公開されないという単一障害点になる、(c) 再実行・多重起動で二重処理が起きる。

## What

公開の可視性とバッチの副作用を分離する:

1. **可視性は read 時の時刻条件**。データに `publish_day` (取得時刻から機械決定される公開予定日。例: `date_jst(t + 3h)` で「前日21:00〜当日21:00 = 当日」を表す) を持たせ、読み取りクエリは常に `publish_day <= VisibleDay(now)` でフィルタ。バッチが死んでいても 21:00 になった瞬間から見える。
2. **バッチは副作用 (push 送信・集計キャッシュ更新・掃除) だけ**を担い、`INSERT INTO batch_runs (day) VALUES ($1) ON CONFLICT DO NOTHING` が 1 行挿入できたときだけ実行する 30 秒 ticker にする。プロセス再起動・多重起動・遅延起動すべてに安全 (遅れて 1 回だけ走る)。
3. 遅延到着データは受信時に「既に公開済みの日か」を判定して翌公開日に付け替える (`EffectiveDay(claimed, receivedAt)`)。猶予 (例 5 分) を式に含める。

## Why

- クライアント側スケジューラ (iOS BGTask) は時刻保証が原理的に不可能、サーバー cron はインフラ依存で観測しづらい。read 時条件は「時計さえ正しければ壊れない」最少の可動部。
- 冪等キー表 (batch_runs) は「実行したか」を DB が覚えるので、ticker が何回評価しても副作用は 1 回。

## How to apply

- publish_day は書き込み時に確定させ、read 側は 1 つの `VisibleDay(now)` 関数に集約 (client/server 両実装があるなら同一規則を両言語の純関数にし、境界標本 — 20:59 / 21:00 / 21:01 — をテストに固定)。
- 時刻依存関数には clock を注入し、テストのハードコード日付は基準時刻からの相対で作る。
- バッチの仕事一覧に「公開」を入れない (入っていたら設計を疑う)。
