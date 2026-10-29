---
title: ASC のスクショが UPLOAD_COMPLETE のまま COMPLETE にならない — checksum null は Apple 側の取りこぼし、削除して 1 枚ずつ reserve し直す
category: gotcha
project: atender
tags: [app-store-connect, asc-api, screenshots, upload]
created: 2026-10-30
sources:
  - sessions/2026-10-29-dbbd5b80.md
---

## Context

atender 1.0.1 で `appScreenshots` を API で 5 枚差し替え (reserve → PUT → `PATCH uploaded:true + sourceFileChecksum`)。全ステップ 200/201 なのに、5 枚中 3 枚が 20 分以上 `assetDeliveryState.state = UPLOAD_COMPLETE` のまま `COMPLETE` にならなかった。

## What

- 滞留した record は `sourceFileChecksum` が **null**、`imageAsset` が `{width:0,height:0}`、`errors: []`。完了した record は checksum が入り `imageAsset` が実寸。つまり commit の PATCH が 200 を返しても Apple 側で処理キューに乗っていない
- 同じ record に checksum 付き PATCH を打ち直すと **500 UNEXPECTED_ERROR** (再 commit 不可)
- **削除 (`DELETE /v1/appScreenshots/{id}`) → reserve → PUT → PATCH を 1 枚ずつ**やり直すと、同じ PNG がそのまま 1 分以内に `COMPLETE` になる。1 回で直らない枚もある (slide-4 は 2 回目で通った)。ファイル側 (RGB 8bit alpha 無し 1320×2868、700〜800 KB) に差は無い = **Apple 側の間欠的な取りこぼし**
- 再 reserve すると並び順がセット末尾に落ちるので、全部 COMPLETE になってから `PATCH /v1/appScreenshotSets/{id}/relationships/appScreenshots` で並べ直す

## Why

ASC の asset 処理は非同期で、commit 直後の record に checksum が反映されないケースが一定確率で起きる。API は成功を返すので呼び出し側からは区別できず、`UPLOAD_COMPLETE` の時間経過で判断するしかない。

## How to apply

- PATCH 直後に `GET` して `sourceFileChecksum` が null なら、待たずに**その record を削除して reserve からやり直す** (待っても COMPLETE にならない)
- 5 枚まとめて上げて放置せず、「PATCH → 60 秒後に GET → 滞留は削除・再 reserve」のループを枚数分回す (最大 3 回)。全 COMPLETE 後に並び順 PATCH → reviewSubmission
- 実装例: `Muraki/.tmp` でなく scratchpad に置いた `reup.py` / `finish.py` (2026-10-30 のセッション) — 次に使うなら `Muraki/scripts/asc.py` の隣に `asc-screenshots.py` として昇格させる価値あり
