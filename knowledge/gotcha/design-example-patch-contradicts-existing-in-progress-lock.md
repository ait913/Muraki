---
title: 設計の「1 回の PATCH で両方替える」例が、既存の進行中ロックと両立しない (wasawasa 連携アカウント)
category: gotcha
tags: [wasawasa, design-review, patch, in-progress-lock, reviewer]
created: 2026-10-14
project: wasawasa
sources: [projects/wasawasa/.designs/20261014-integration-accounts.md, projects/wasawasa/.designs/20261005-app-upload-xcode-cloud.md]
---

## Context
連携アカウント設計 (2026-10-14) の挙動仕様 IE5 / IE9 / 開発フロー I4 が、親設計 (3a §9-2) の既存制約と食い違った。Reviewer のテストが 2 本赤になったが、実装は 3a のとおりで設計文面の方が誤り。

## What
1. IE5 / I4: 有効な環境の Apple アカウントを替えるとき `{apple_account_id, xcode_cloud_product_id, xcode_cloud_workflow_id}` だけ (repository は省略) で 200 とした。3a §9-2 は repository の自動選択を「有効化時だけ」とするので、保存済みの旧 product の repository が残り 422 `xcode_cloud_repository_not_found`。
2. IE9: 「進行中でもアカウントを替えられる」の例が product / workflow も替える PATCH。3a §9-2 は product / workflow の変更を進行中は 409 `app_upload_in_progress` にするので、Apple の付け替えは API では進行中に行えない (Apple を替えるには product も替える必要があるため)。

## Why
新しい許可 (進行中でも X を替えられる) を書くとき、X の変更に連動して必須になる他のキー (product) が既存の禁止リストに入っていないかを引かなかった。例示の本文だけが仕様の根拠になり、既存節との照合が漏れた。

## How to apply
- Architect: 「進行中でも許す」「1 回の保存で複数キーを替える」と書くときは、同じ PATCH に載る全キーについて既存の禁止・自動補完の規則 (進行中 409、有効化時だけ自動選択) を grep して突合する。
- Reviewer: 設計の例示本文が赤くなったら、実装を疑う前に親設計の同じキーの規則を引く。意図 (スナップショット) を別の経路 (DB で付け替え / 連動しないキーの Firebase) で検証し分け、文面どおりの 1 本は赤のまま設計の不備として報告する。
