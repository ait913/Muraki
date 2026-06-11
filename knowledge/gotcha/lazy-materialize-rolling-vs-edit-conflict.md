---
title: lazy materialize の rolling 補充が「生成 record の手動編集」を壊す
category: gotcha
tags: [materialize, recurring-rule, lazy, idempotency, api-design, conflict]
created: 2026-06-08
project: kinketsu-taisaku
sources:
  - Muraki/projects/kinketsu-taisaku/.designs/20260608-mvp-core.md (§5.1 §5.4 §5.6)
---

## Context

定期ルール (月次) から未確定 record を未来へ実体生成する materialize 方式。
cron を使わず「書き込みトリガー + アクセス時 rolling 補充 (lazy)」を採用したアプリで、
reviewer が設計 doc だけからテストを書いて API に当てたら、生成 record の PATCH が常に 404 になった。

## What

設計内に**同時成立しない 3 つの仕様**が紛れ込んでいた:

- §5.1 materialize: 既存の `paid=false AND isManuallyEdited=false` な生成 record は
  「**削除して再生成**」(最新ルール内容を反映)。
- §5.6 rolling 補充 (ensureMaterialized): requireAuth 後の共通フックで毎アクセス実行。
  性能 note は「**不足月のみ INSERT、既存月は SELECT で存在確認するだけ**」と書く。
- §5.4: 生成 record を PATCH すると `isManuallyEdited=true` を立てて以降保護する。

実装は §5.1 の「未編集なら削除→再生成」を **rolling 補充にも適用**した。結果:

- 同じ rule・同じ月の生成 record の id が、GET を 2 回叩くだけで 14 → 27 と変わる
  (毎アクセスで delete + 新 INSERT)。§5.6 の「存在確認だけ」という性能保証が嘘になる。
- GET で取得した id を PATCH しようとすると、**PATCH リクエストの前段 rolling 補充**が
  その record を削除済みなので必ず `404 NOT_FOUND`。§5.4 の「生成 record を編集」が
  構造的に達成不可能。materialize 方式を採った最大の動機
  (「今月の給料だけ金額変更」を生成済み record の直接編集で実現) が機能しない。

## Why

「未編集なら最新ルールを反映するため削除再生成」は **rule の内容が変わった時 (rule PATCH/POST) だけ**
正当な操作。それを**毎アクセスの rolling 補充でも無条件に**走らせると、

1. id が毎回変わり冪等でなくなる (URL/参照が安定しない)、
2. 編集操作とレースして編集対象が消える、
3. delete+insert を毎アクセスで繰り返し I/O が膨らむ (§5.6 の性能前提が崩壊)。

rolling 補充の本来の役割は「窓 (現在月+N) の**不足月を埋める**」だけ。既存月の record は
内容が古くても触ってはいけない (内容更新は rule 変更イベント側の責務)。

## How to apply

materialize 系を設計する時、**「再生成 (delete+insert)」と「補充 (不足分だけ insert)」を別操作として分離**する:

- **補充 (ensureMaterialized / rolling)**: `(sourceRuleId, yearMonth)` が**無い月だけ** INSERT。
  既存 record は paid/edited に関係なく**一切触らない**。冪等で id 安定。
- **再生成 (re-materialize)**: rule の POST/PATCH/active 変更/settings 変更など
  **内容が変わったイベント時のみ**。このとき未来月の `paid=false AND isManuallyEdited=false`
  を delete+insert する。

設計 doc レビュー観点として、materialize 系には必ず確認する:
- 「毎アクセスで走る経路」と「内容変更で走る経路」で **delete を許すのは後者だけ** になっているか。
- 生成 record の id が API アクセス間で安定するか (= PATCH/DELETE が安定して効くか)。
- 「生成物を手動編集できる」要件があるなら、編集前の前段フックが編集対象を消さないか。

reviewer 側の実務: 生成 record の id を GET で 2 回取って**同一かを assert** すると、
この「毎アクセス再生成」バグを一発で炙り出せる。
