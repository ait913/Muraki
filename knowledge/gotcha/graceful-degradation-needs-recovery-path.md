---
title: 意図的な縮退モードは復帰経路とセットでないと永久障害になる
category: gotcha
project: omatase
tags: [go, resilience, db, startup, restart-policy, degraded-mode]
created: 2026-08-08
sources:
  - omatase 本番障害 2026-08-06〜08 (/v1/* が 2 日間 503)
  - apps/backend/cmd/omatase/main.go の旧 connectDB (PR #12 で修正)
model-era: fable-5
---

## Context

omatase backend は「DB が無くても /healthz は 200 を返し、/v1/* だけ 503 に縮退する」意図的な設計を持っていた。導入時は正しい判断 (当時のデプロイ環境に DATABASE_URL が無く、fatal にすると本番が即死した)。コメントに「DB 必須になったら fatal に切り替えろ」と TODO も書いてあった。

## What

- **縮退モードに入る経路はあるが、出る経路が無かった** — DB 接続は起動時 1 回きり。失敗すると nil pool のまま永久に 503。pgx pool の自動再接続は「pool が存在する」場合の話で、pool 生成自体に失敗した場合は誰も再試行しない
- サーバーが毎日自動再起動する運用 (`ais-auto_reboot.timer`) で、DB より API が先に上がる順序を引くと、DB が数十秒後に生きても API は二度と繋ぎに行かない → **2 日間の実障害**
- 追い打ち: /healthz は DB を見ないため、Coolify のステータスは `running:healthy` のまま。**監視上は何も起きていないように見えた**
- コード内 TODO (「必須になったら fatal に切り替えろ」) は、その条件が満たされた再構成 (2026-07-30) の時に誰も履行しなかった。**設計docにも台帳にも載っていない借りはコメントの中で死ぬ**

## Why

縮退は「入る条件」だけ設計されがちで、「出る条件」が設計されないと片道切符になる。特に起動時 1 回きりの初期化 + 例外を握って続行、の組み合わせは「プロセスは健康・機能は死亡」という監視の盲点を作る。

## How to apply

- 意図的な縮退を入れるときは**復帰経路 (リトライ / 再接続 / 再試行の主体) を同じ PR で設計する**。書けないなら fail-fast にする
- 依存が起動時に無いかもしれない環境 (毎日再起動・オートスケール) では、**接続リトライ (有限) → exit(1) → restart policy 委譲**が既定。restart policy が `unless-stopped`/`always` であることを裏取りしてから採る
- healthz が依存を見ない設計なら、「healthy 表示のまま機能が死ぬ」ケースを台帳 (known-failures) に明記して監視の盲点を可視化する
- 「〜になったら切り替えろ」型の TODO コメントは書いた時点で負債台帳 (.knowledge) に登録する。コメントだけの TODO は条件が満たされた瞬間に思い出されない

## 追記 (2026-08-08): 同型 2 例目

`apps/web/Dockerfile` にも「public/ は現状存在しないので COPY しない。追加したら下行を有効化すること」というコメントアウト行が眠っており、LP で public/ を初めて追加した際に誰も有効化せず、**スクショが本番で 404 になった** (ローカルの next build は通る)。「〜になったら有効化しろ」型のコメントは条件が満たされた瞬間に思い出されない — 2 日間障害 (DB fatal 化 TODO) と同一週に 2 例目。この型を書くときは台帳 (.knowledge) 登録が必須。
