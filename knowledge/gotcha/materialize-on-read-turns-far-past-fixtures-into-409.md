---
title: materialize-on-read (読んだ瞬間に状態を書く) を入れると、遠い過去日付の fixture が「GET したら 409」になる
category: gotcha
project: omatase
tags: [testing, integration, go, postgres, archive, fixtures, lazy-materialization]
created: 2026-07-30
sources:
  - "omatase .designs/20260730-rebuild-screens.md §7.4 (自動アーカイブの実体化)"
  - "omatase apps/backend/internal/http/rebuild_screens_integration_test.go (Reviewer 2026-07-30)"
  - "omatase apps/backend/internal/http/rebuild_api_integration_test.go TestAPICurrentPlanIsPerMember (2020/2021 の start_time)"
---

## Context

omatase の自動アーカイブは **cron を立てず「読み取り時に実体化する」** 方式 (`GET /events/{id}` /
`GET /events` / `GET /invites/{token}` の入口で `MaterializeArchived` を呼び、期限超過なら
`events.archived_at` を書く)。アーカイブ済イベントへの書き込みは全て 409 `event_archived`。

一方 integration テストの慣習として、「もう始まっているプラン」を作るのに
**`start_time: "2020-01-01T00:00:00Z"` のような遠い過去**を使っていた (時刻導出の検証で
`now` に依存したくないため。基盤編のテストがこの形)。

## What

**遠い過去の fixture は「最初の GET で自分自身をアーカイブする」ので、そのあとの書き込みが全部 409 になる。**

Reviewer が書いた新テストが 2 本落ちた:

```
PUT current-plan: status = 409, want 200; body={"error":{"code":"event_archived",...}}
PUT checklist check: status = 409, want 200; ...
```

どちらも「**snapshot を 1 回読んだ直後**の書き込み」で落ちている (checklist の item_id を取るために
GET したのが引き金)。実装は §7.4 のとおり正しく、**落ちたのはテストの fixture**。

さらに悪いのは既存テストの側:

- `TestAPICurrentPlanIsPerMember` は `2020-01-01` / `2021-01-01` を使っており、**GET した時点で
  イベントが archived になっている**。だが読み取りしかしないので **緑のまま**
- つまり「読み書き混在のテストを 1 行足した瞬間に落ちる」時限爆弾が緑の中に埋まっている

## Why

materialize-on-read は「読み取りが副作用を持つ」設計なので、**テストの読み取りが fixture の状態を変える**。
遠い過去の日付は「開始済」を表すために選ばれたのに、同時に「猶予期限も超過」を意味してしまう
(猶予 7 日に対して 6 年前)。日付リテラルの意図 (開始済) と、実装が読む意味 (期限切れ) が食い違う。

`hardcoded-future-dates-decay-into-baseline-failures.md` の裏返し: あちらは
「近未来を焼くと数日で腐る」、こちらは「**遠い過去を焼くと lazy な状態遷移を踏む**」。

## How to apply

- **「開始済」を表す fixture は `now - 1〜2h` で作る。** 遠い過去は使わない
  (Go なら `time.Now().UTC().Add(-2*time.Hour).Format(time.RFC3339)` を返すヘルパを 1 本置く)
- **遠い過去を意図的に使うのは「期限切れを作りたいとき」だけ**にし、テスト名にそう書く
- materialize-on-read を**新規に導入する PR では、既存テストの日付リテラルを棚卸しする**。
  「読み取りだけのテストは緑のまま」なので grep で見つけるしかない
  (`grep -rn "20[0-2][0-9]-[0-1][0-9]-" *_test.go`)
- **読み取りだけのテストには「ワイヤ」を 1 行張る** — 末尾で `select archived_at ... is null` を assert すると、
  緑のまま埋まる時限爆弾が二度と作れない。omatase では既存 `TestAPICurrentPlanIsPerMember` に張り、
  fixture を 2020/2021 に戻す負のコントロールで `archived_at = 2021-01-08T00:00:00Z`
  (= 最終プラン + 猶予 7 日) を検出できることを実証した。**この値が `now()` でなく「期限そのもの」**なのも
  同時に確認できる (実体化 SQL が `archived_at = deadline` を書く仕様の裏取りになる)
- 偽 fail の切り分け: `409 event_archived` が**GET の直後だけ**に出るなら実装ではなく fixture。
  `select archived_at from events` を 1 回引けば 5 秒で確定する (role note 35 の系譜)
