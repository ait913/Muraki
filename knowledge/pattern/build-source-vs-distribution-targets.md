---
title: アプリ配布は「ビルド元 (1)」と「配布先 (N、種別付き)」に分け、ビルドが違う配布先は別 run に束ねる
category: pattern
tags: [app-distribution, testflight, firebase-app-distribution, xcode-cloud, state-machine, wasawasa]
created: 2026-11-03
project: global
sources:
  - "Muraki/projects/wasawasa/.designs/20261103-distribution-targets.md"
---

## Context
wasawasa のアプリアップロード (Xcode Cloud → Firebase App Distribution) に TestFlight を足す要望。出口が 1 本・Firebase 列が環境にフラットに焼き付いていて、「同じ環境で両方」「TestFlight だけオン/オフ」「将来 Play / App Store 提出」を表せなかった。

## What
- 環境に **ビルド元** (ビルドするアカウントと product / workflow、1 つ) と **配布先** (`kind` + 種別ごとの宛先列 + `enabled` + `position`、0..N) を分ける。配布先は 1 表 + 種別ごとの NULL 許容列 + kind ごとの CHECK (JSON 列にしない: CHECK と FK を張るため)
- 配布先の入力は成果物の種別 (`ios_adhoc_export` / `asc_build` / 将来 `aab`)、出力は 2 系統 (即時 URL / 状態遷移を追う)。URL を単一列に持つ台帳 (`builds.distribution_url`) は残し、配布の記録を子表 (`build_distributions`) に足す
- run の状態は「ビルドまで共通 → `delivering` (配布先ごとの子行が `waiting → running(stage) → done/failed/skipped`) → succeeded / partially_succeeded / failed」。最初の done でビルドを登録し、残りは配布記録を足す
- 配布先ごとに workflow を上書きできるようにし、実効 workflow で束ねて **束ごとに別 run** (= 1 ビルド)。1 run に複数ビルドを持たせると検証済みの投入・照合の状態機械を全部書き直すことになる
- 「選んでも正解が 1 つ」のアカウント (TestFlight はビルドと同じ Apple チーム) は配布先に持たせない
- 既存の 1 件だけの構成 (bloom の Firebase 1 件) は、DTO の steps・Slack カードが旧と完全一致になる規則にして既存テストの書き換えを最小にする

## Why
配布系は入力 (成果物) と出力 (URL か状態) の 2 軸で違い、それ以外 (アカウント・宛先) は種別固有。種別ごとの差分を列と adapter に閉じ込めると、種別の追加が「CHECK に値・列・adapter・フォーム 1 つ」で済み、状態機械に触れない。

## How to apply
- 外部への配布・通知・同期の「出口」を設計するときは、まず出口が 1 個に焼き付いている列・CHECK・状態名 (`uploading` のような出口固有の status) を grep で全部挙げる
- 同じリポジトリに「未実装だが承認済み」の doc が同種の表 (例: パイプライン専用の配布先登録) を持っていないか grep し、表を 1 つに寄せて置換表に載せる
