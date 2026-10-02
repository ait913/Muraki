---
title: 外部 PaaS (Coolify 等) のデプロイを自前アプリから実行・追跡する — DB 永続の run 行 + lease + 終端前の後始末
category: pattern
tags: [deploy, coolify, poller, lease, state-machine, outbox, notification, restart-safe, nextjs-instrumentation]
created: 2026-10-03
project: global
sources:
  - wasawasa Phase 2 リリース前ゲート (Codex 静的レビュー NO-GO 2026-10-03、Leader 裏取り) — lease 世代・結果不明状態・write-ahead を追加
  - Muraki/projects/wasawasa/.designs/20261003-deploy-mcp-slack-responsive.md §7, §8, §9
  - Muraki/projects/wasawasa/.knowledge/research-20261003-deploy-mcp-responsive.md
---

## Context

管理画面 (wasawasa) の「デプロイ」ボタンで、Coolify アプリのブランチを PATCH → `POST /deploy` → 完了まで poll → 結果を台帳と Slack に流す。本番ホストは毎日再起動し、アプリ自身も rolling update で旧新 2 コンテナが同時に動く。外部 API は「同一 commit がキュー中なら skipped を返し、応答の deployment id は保存されない幽霊」「キュー中にブランチを変えると後続の job が新ブランチで走る」などの罠を持つ。

## What

1. **run 行を DB に持ち、状態機械で進める**: `pending → queued → running → succeeded | failed`。全遷移は「親 (Project) ロック → run 行 `FOR UPDATE` → status が期待値のときだけ書く」。期待値と違えば何もしない = 二重実行が無害
2. **環境あたり進行中 1 本を部分 unique で保証**: `UNIQUE (environment_id) WHERE status IN ('pending','queued','running')`。並行受付は片方が 409
3. **プロセス内ループ + 世代つき lease**: `setInterval` (Next.js なら `instrumentation.ts` の migration 後) が非終端 run を拾い、`UPDATE … SET lease_owner = me, lease_gen = lease_gen + 1, lease_until = now()+60s WHERE lease_until IS NULL OR lease_until < now() RETURNING lease_gen` で取る。**時間上限だけでは足りない** (止まっていた旧処理が期限後に外部へ書ける): 処理中は 20 秒ごとに `WHERE owner = me AND gen = g` で更新し、**外部への書き込み直前に同じ条件で所有確認**、run 行への全 UPDATE も owner + gen を条件にする。外部呼び出しのタイムアウト < lease を不変条件として起動時に検査する。lease を持たない経路 (ユーザーのキャンセル等) は「記録だけ」にして status を変えさせない
4. **投入前に外部キューを確認し、混んでいたら断る**: 自分がブランチを PATCH する前に「他の queued / in_progress」が無いことを見る。あれば `busy` で失敗 (ブランチに触っていないので後始末も不要)
5. **外部書き込みの結果は 3 値 (applied / not_applied / unknown) で、unknown を状態として持つ**: タイムアウト・送信後の切断・5xx は「作られたかもしれない」。終端にもせず後始末もせず `dispatch_unknown` に置き、外部の一覧から `is_api` かつ投入時刻以降・他の run が未採用の行を探して採用 (deployment id に部分 unique)、猶予 (60 秒 + 照合 N 回) 後も無ければ失敗。照合は読み取りだけなので打ち直し (二重投入) より安全。**意図は書く前に永続化 (write-ahead)**: ブランチ PATCH の前に「変更前の値 + 意図」、POST の前に `dispatch_started_at` を書き、復旧時は外部の実値と照合して戻す (実値 = 自分の値なら戻す / 元の値なら不要 / 別の値なら触らない / 読めないなら『未確認』を表示)
6. **幽霊 id を追わない**: skipped 応答の id は捨て、一覧から実在の queued / in_progress を採用する。poll で 404 が連続 N 回なら `lost`
7. **台帳の切替は外部の成功時に行う**: 「サーバー更新 + バージョン切替」の操作で、切替を受付時に確定すると失敗時に台帳だけ新しくなる。成功 tx で切替・成果物登録・完了 Event をまとめて書く。外部ステップが無い操作 (切替だけ) は受付 tx で完了させる
8. **後始末 (ブランチ復元) は run を終端にする前に行う**: 終端後に戻すと、その隙に受け付けた次の run の PATCH と競合する。進行中のうちは部分 unique が次の受付を止めている
9. **通知は Event と同じ tx で配送行を積む (outbox)**: Event INSERT の直後にルール照合して `deliveries(pending)` を INSERT。送信は同じループが `FOR UPDATE SKIP LOCKED` で claim。送信失敗は配送行に残すだけで本処理に影響しない
10. **外部への長時間処理を AI ツール (MCP) から呼ぶときは即時に run id を返す** + 状態取得ツール。待つ必要は台帳と通知が担う

## Why

- 状態をメモリに持つ poller は再起動 1 回で迷子の run を作る。DB の行 + lease なら「誰が今それを進めているか」が DB で分かり、プロセスの数に依存しない
- 外部 API の重複排除・キュー・設定の遅延読み込み (job 起動時にブランチを読む) は、こちらの「PATCH → POST」の 2 手の間に他者が入ると壊れる。2 手の前に外部の状態を確認して断るのが、リトライや猶予窓より確実
- 「成功したら台帳を変える」にすると、失敗時の不変条件が「何も変わらない」の 1 行で書ける。Reviewer もテストを書きやすい

## How to apply

- 設計 doc に (a) 状態遷移表 (契機・書くもの)、(b) 投入の各段とその失敗理由、(c) lease の SQL、(d) 期限・poll 周期・404 許容回数の定数と根拠 (外部の実測所要時間)、(e) 起動時に「投入途中」の run をどう判定するか、(f) 後始末と終端確定の順序、を書く
- 挙動仕様に「サーバーを止めている間に外部が完了 → 起動後に完了処理」「lease が他者のものなら触らない」「処理中に lease を奪われたら外部に書かない」「POST が applied_then_timeout / timeout のそれぞれで採用 / 未作成失敗」「並列受付で片方 409」「外部が skipped を返した時に幽霊 id を保存しない」を入れる
- 外部の応答本文は DB (失敗詳細・Event) に保存せず分類だけにする。ログは URL・Bearer・`token=`・長い乱数列を伏せた抜粋
- 状態を持つ処理の tx の中では、渡された tx 以外の DB 接続を使わない (プール上限の並列で全停止する)
- 列の削除は「コードから外すリリース」と「DROP するリリース」を分ける (rolling update 中の旧コードが全列 SELECT で落ちる)
- テストは外部のスタブに「状態を手で進める」制御 endpoint と「poll ごとに自動で進める」モードを両方持たせ、ループ周期を env で短くする (200ms)。固定 sleep でなく API を引いて状態を待つ
- Coolify 固有の罠は [[tool-quirk/coolify-api]] を見る
