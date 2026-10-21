---
title: 自宅 Coolify スタックのセキュリティ下限 (2026-10 棚卸し)
category: library
tags: [security, cve, node, go, postgresql, postgis, docker, nginx, mcp-sdk, nodemailer, hono, emudhra]
created: 2026-10-22
project: global
sources:
  - https://nodejs.org/en/blog/vulnerability/october-2026-security-releases
  - https://endoflife.date/nodejs
  - https://pkg.go.dev/vuln/GO-2026-6809
  - https://www.postgresql.org/about/news/postgresql-186-1711-1615-1519-1424-and-19-beta-3-released-3365/
  - https://hub.docker.com/v2/repositories/postgis/postgis/tags?name=16-
  - https://docs.docker.com/engine/release-notes/29/
  - https://github.com/coollabsio/coolify/releases/tag/v4.4.7
  - https://api.osv.dev/v1/query
---

## Context
2026-10-22 に Touri の自宅 Coolify で動くアプリ群 (Node/React/Go/PG/nginx/Python/各 npm lib) の 8〜10 月の脆弱性・EOL を棚卸しした時の、次回も効く事実だけ抜粋。個別 CVE の全リストは session 2026-10-22-acd89e01 を参照。

## What
- **eMudhra 中間 CA 失効 (2026-10 中旬)** は 1 つの事案で複数レイヤの更新が同時に出た: Node (10/21 release の ca-cert 更新)、Go `crypto/x509` denylist (CVE-2026-111943, go1.26.10 / 1.27.3)、Docker Engine 29.9.2 (Go runtime)、certifi (emSign root 削除、python.org 告知)、cloudflared 2026.10.3、Coolify Sentinel 1.1.2。**TLS を話す Go/Node バイナリは全部ビルドし直し**が必要 (OS の trust store 更新だけでは Go の embedded denylist は効かない)
- **`postgis/postgis:<pg>-3.4` タグは 2024-10-14 で凍結** (16-3.4 / 17-3.4 とも)。PostGIS マイナーごとにタグが切られ、古い PostGIS マイナーは PG のパッチを受け取らない。現行は `16-3.5` (2026-08-31) / `16-3.6` (2026-10-19)。「ビルド時に最新 pull」でも中身は PG 16.4 相当のまま
- **Node 20 は 2026-04-30 EOL**。最終 20.20.2 (2026-03-24)。7 月・10 月の High 修正 (HTTP/2 UAF、Brotli OOB write RCE 等) は 20 系に出ていない。`node:20-alpine` は 2026-04-15 以降更新なし
- `node:24-alpine` は alpine3.23 / 3.24 ベース (3.22 タグは無い)。`nginx:alpine` は alpine3.24
- OSV の npm 照会 (`api.osv.dev/v1/query`) と `gh api /advisories?ecosystem=npm&affects=<pkg>` を併用すると、片方にしか出ない advisory (better-auth の duplicate advisory 等) を拾える

## Why
「ビルド時に最新を pull」は **タグが動いていれば** 効くが、postgis の旧マイナータグや EOL ラインのタグは動かない。CA 失効系はライブラリ内蔵の trust 判定 (Go) が絡むので OS パッケージ更新とは別に再ビルドが要る。

## How to apply
- postgis は `16-3.6` 系 (または `17-3.6`) に tag を上げる。PostGIS 3.4→3.6 は `ALTER EXTENSION postgis UPDATE` が必要
- Node 20 残存アプリは 22 or 24 へ。24 は 2026-10-20 から Maintenance LTS、26 が Active LTS (2026-10-27〜)
- 全 Go / Node イメージを 2026-10-21 以降に再ビルドして eMudhra denylist を取り込む
- npm 側の下限 (2026-10-22 時点): `@modelcontextprotocol/sdk>=1.32.1`, `@modelcontextprotocol/server>=2.3.1`, `hono>=4.13.11`, `nodemailer>=10.0.9`, `sharp>=0.35.5`, `react-server-dom-*>=19.2.9 / 19.3.1`, `better-auth>=1.6.22` (7 月の ATO 修正), `next-auth 5.0.0-beta>=beta.32`
