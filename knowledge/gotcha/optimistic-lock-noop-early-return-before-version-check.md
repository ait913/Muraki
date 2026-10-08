---
title: 楽観ロックで「変更なし」の早期 return が版検査より前にあると、no-op PATCH が他者の版を持ち帰る
category: gotcha
tags: [optimistic-lock, updated_at, 409, no-op, patch, client-queue]
created: 2026-10-09
project: global
sources:
  - "projects/wasawasa/lib/domain/databases.ts updateRow (2026-10-09 修正)"
  - "projects/wasawasa/.designs/20261007-databases.md §6-8 / §6-12"
  - "sessions/2026-10-09-9f2cb1ff.md (Codex 第 6 パス I1)"
---

## Context

wasawasa の DB 行 `updateRow` は `expected_updated_at` (ms 単調) で 409 `row_conflict` を返す楽観ロック。実装は「patch を当てて変更が無ければ現在行を 200 で返す」を**版検査より先**にしていた (無駄な版更新と Event を避けるため)。

## What

他者が先に同じ値にしていると、自分の古い版の PATCH が「変更なし」で 200 になり、応答に**他者の版** (`updated_at = t2`) が載って返る。クライアントがその応答の版を「自分の成功応答」として次の PATCH の `expected_updated_at` に使うと、他者の別セルの更新を無警告で上書きできる (Codex 第 6 パス I1、再現 6 手順)。

## Why

楽観ロックの契約は「`expected` が現在の版と違えば、内容に関わらず拒否」でないと、クライアント側で「応答の版 = 自分が操作した版の後継」という前提が成り立たない。no-op の最適化は版検査の**後**に置けば、同じ効果 (版を進めない、Event を出さない) を保ったまま契約を守れる。

## How to apply

- 楽観ロックのサーバー実装は **(1) 版検査 → (2) 変更なしなら 200 (版据え置き) → (3) 更新** の順で書く。設計 doc の検査順序表にもこの順で書く (wasawasa 3c §6-12)
- 既存テストで「古い版で同一内容を再送 → 200」を期待しているものがあれば、それは契約違反を固定しているので「409」に置換する (wasawasa DBC2 / DBM4)
- クライアントは、`expected` に入れる版を「ユーザーが見て操作した版」か「自分の成功応答の版」に限定し、GET / refresh で取り込んだ版を pending の job に使わない (詳細: [[tool-quirk/codex-gate-same-component-three-rounds-change-the-root]])
