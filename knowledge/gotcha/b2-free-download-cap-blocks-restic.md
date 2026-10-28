---
title: Backblaze B2 の無料枠は日次 download / Class B 上限があり、復元テストを 1 回回すと restic が全操作 Access Denied になる
category: gotcha
project: global
tags: [backblaze, b2, restic, backup, caps, s3]
created: 2026-10-29
sources:
  - aiserver2 での実走 (sessions/2026-10-29-b45758d0.md 53)
  - B2 native API の応答 `{"code":"download_cap_exceeded","message":"Cannot download file, download bandwidth or transaction (Class B) cap exceeded. See the Caps & Alerts page to increase your cap."}`
---

## Context

aiserver2 のオフサイトバックアップ (restic → B2 S3 API) を導入した夜、初回バックアップ 1.08GiB + 復元テスト (全 DB dump と volume 800 ファイルを restore + `check --read-data-subset`) を回した直後から、restic の `snapshots` / `backup` が `Stat(<config/>) failed: Stat: Access Denied` で全部失敗した。

## What

- B2 の無料アカウントは **1 日の download 帯域 (1GB) と Class B トランザクション数に上限**があり、超えると HeadObject / GetObject が **403 Access Denied** になる (S3 API ではエラー本文に理由が出ない。native API の `b2_download_file_by_name` を叩くと `download_cap_exceeded` が読める)
- restic は `backup` でも repo の `config` / index を読むので、上限超過中は**バックアップも失敗**する (A13 の dead-man が翌日に鳴る)
- 上限は日次 (UTC 0:00 リセット = JST 09:00)。03:30 JST の timer は翌朝まで引っかかる
- `rclone lsf` (ListObjects = Class C) は通るので「鍵が壊れた」ように見えない。切り分けは native API のエラー本文

## Why

復元テストは「全量を読む」ので download を食う。無料枠の設計は storage (10GB) ばかり見て download 上限を見落とした。

## How to apply

- B2 を本番バックアップ先にするなら **Caps & Alerts で上限を上げる (支払い方法の登録が要る)**。無料枠のままなら復元テストは月 1 回・subset に絞り、`check --read-data-subset` の割合を下げる
- restic が Access Denied を返したら、鍵を疑う前に native API で `download_cap_exceeded` を確認する
- 上限超過中は snapshot を取れないので、切替前の退避は local tar (`/var/backups/aiserver/migrate/`) で代替し、後日 restic に入れる
