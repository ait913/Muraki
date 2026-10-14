---
title: Cloudflare 配下 (Coolify API / *.appily.run) は Python-urllib の既定 UA を Error 1010 で弾く
category: gotcha
project: global
tags: [cloudflare, python, urllib, coolify, user-agent]
created: 2026-10-15
sources:
  - 実測 2026-10-15 (bloom scripts/review_env.py、n-wasabi/bloom #23 #24)
---

## Context
Python 標準の `urllib.request` で `https://coolify.aisaba.net/api/v1/...` や `https://*.appily.run/` を叩くスクリプト。curl では通るのに Python からだけ 403 になる。

## What
- 応答は 403 JSON `"title":"Error 1010: Access denied","detail":"The site owner has blocked access based on your browser's signature."`。原因は既定の UA `Python-urllib/x.y` (Cloudflare の Browser Integrity Check 系)
- 独自 UA (例 `bloom-review-env/1`) なら 200。curl の既定 UA も通る

## Why
Cloudflare が既知のスクリプト UA をシグネチャで弾く。サーバー (Coolify / Nginx / アプリ) までリクエストが届いていないので、サーバー側のログには何も残らない。

## How to apply
- モジュール先頭で `opener = urllib.request.build_opener(); opener.addheaders = [("User-Agent", "<tool>/1")]; urllib.request.install_opener(opener)`
- **`build_opener(...)` で別の opener を作る箇所 (redirect 無効化など) は install_opener の UA を引き継がない**。その opener にも `addheaders` を付ける
