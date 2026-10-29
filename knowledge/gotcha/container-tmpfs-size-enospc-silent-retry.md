---
title: read-only コンテナの --tmpfs /tmp:size=64m が成果物の一時保存で ENOSPC → 外形は「送信中」のまま無限再試行
category: gotcha
project: aiserver / wasawasa
tags: [docker, tmpfs, read-only, coolify, custom_docker_run_options, app-upload, xcode-cloud, firebase]
created: 2026-10-29
sources:
  - Muraki/sessions/2026-10-29-99bd9e0b.md (#26〜27)
  - Muraki/projects/aiserver/.designs/20261029-aiserver2-hardening.md §6-1
---

## Context

aiserver2 の硬化 (2026-10-29) で app 全数に COMMON `--read-only --tmpfs /tmp:rw,noexec,nosuid,size=64m` を入れた。同日夜、bloom の dev ビルド (wasawasa `app_upload` = Xcode Cloud → IPA 取得 → Firebase App Distribution) が「Firebase に送信中」で 15 分以上止まり、`artifact` ステップの時刻だけが進み続けた。

## What

- wasawasa は IPA を `os.tmpdir()/wasawasa-app-upload/<run>` に書く (`lib/domain/app-uploads.ts:85`)。IPA は 64 MB を超えるので `ENOSPC: no space left on device` で write に失敗し、worker が同じ run を再試行し続ける (ホストのディスクは 125 GB 空きで、`df` では気付けない)
- 外形 (MCP `app_upload_status`) は `uploading` のまま、`failure` は null。コンテナログ (`GET /applications/{uuid}/logs`) で初めて `[app-upload] … ENOSPC` が見える
- 修正: `custom_docker_run_options` の `/tmp` を `size=1g` に PATCH → `POST /applications/{uuid}/restart`。再起動後に pending の run は自動で再開し、そのまま完了した

## Why

tmpfs の size は「書くもののサイズ上限」で、ファイルを一時保存するサービス (成果物・アップロード・画像変換) には 64m が小さすぎる。read-only 化と同時に入れると、書けない場所が `/tmp` しか無いので逃げ道が無い。

## How to apply

- read-only + tmpfs を入れる前に、サービスが `/tmp` に何を書くか (`os.tmpdir()`、`mkdtemp`、`createWriteStream`) を grep し、最大サイズで size を決める。例外は硬化 doc の表に行として残す
- 「送信中のまま進まない」「ステップの時刻だけ進む」は worker の無限再試行の形。まずコンテナログで `ENOSPC` / `EROFS` を探す
- Coolify の app uuid は clone (destination 移行) で変わる。`logs` が 404 なら `GET /applications` で名前から引き直す
- wasawasa の `app_upload` は環境の現在リリースのブランチをビルドするので、`deploy` でリリースを切り替えた直後は `deploy_status` の `version_switched: true` を見てから呼ぶ (先に呼ぶと旧ブランチをビルドし、cancel しても Xcode Cloud 側のビルドは止まらない)
