---
title: Cloudflare Workers 常駐アプリの土台 2026-10 — D1 上限と FTS5 (export 不可・日本語は trigram 3 文字以上)・R2・Static Assets SPA・Next.js は vinext 推奨へ・better-auth は workerd で動く
category: library
project: global
tags: [cloudflare, workers, d1, r2, fts5, static-assets, hono, opennext, vinext, better-auth, wrangler, custom-domain, queues]
created: 2026-10-24
sources:
  - https://developers.cloudflare.com/d1/platform/limits/
  - https://developers.cloudflare.com/d1/platform/pricing/
  - https://developers.cloudflare.com/d1/best-practices/import-export-data/
  - https://developers.cloudflare.com/d1/sql-api/sql-statements/
  - https://developers.cloudflare.com/workers/platform/limits/
  - https://developers.cloudflare.com/workers/static-assets/routing/single-page-application/
  - https://developers.cloudflare.com/workers/framework-guides/web-apps/nextjs/
  - https://developers.cloudflare.com/workers/configuration/routing/custom-domains/
  - https://developers.cloudflare.com/dns/manage-dns-records/reference/wildcard-dns-records/
  - https://developers.cloudflare.com/r2/pricing/
  - https://developers.cloudflare.com/queues/platform/limits/
  - https://github.com/opennextjs/opennextjs-cloudflare/releases
model-era: sonnet-5
---

## Context

AIS Mail Phase 3 を Workers に常駐させる設計前調査 (2026-10-24)。詳細: `projects/ais-pass/.knowledge/research-phase3-mail-workers-20261024.md`。

## What

- **D1 (Paid)**: DB 10 GB (引上げ不可)、行/文字列/BLOB 2 MB、SQL 文 100 KB、bound 100、1 呼び出し 1,000 クエリ、LIKE パターン 50 byte、Time Travel 30 日。読み 250 億行/月込・書き 5,000 万行/月込・5 GB 込。`BEGIN` は使えず原子的複数文は `db.batch()`。Drizzle は `drizzle(env.DB)` (drizzle-orm 0.45.4)、migration は `wrangler d1 migrations apply <DB名>`、drizzle-kit の入れ子フォルダには `migrations_pattern` が要る。
- **FTS5 は D1 で使える** が、**仮想テーブルを含む DB は `d1 export` 不可** (DROP → export → 再作成)。仮想テーブルに `ON CONFLICT DO UPDATE` 不可 (`INSERT OR REPLACE`)。実測 (wrangler 4.152.0 の local D1): `tokenize='trigram'` は日本語 3 文字以上でヒット、**2 文字は 0 件** → LIKE フォールバックか `Intl.Segmenter` 分かち書き。本番 D1 での trigram は未実測。
- **R2**: 10 GB-月無料、$0.015/GB-月、egress 無料、Class A $4.50/百万、Class B $0.36/百万。Worker から `get().body` をそのまま `Response` に流せる。
- **Workers (Paid)**: CPU 既定 30 秒・最大 `limits.cpu_ms`=300,000、メモリ 128 MB、サブリクエスト 10,000、Cron 250、$5/月 + 1,000 万 req + 3,000 万 CPU ms 込。静的アセット要求は無料。Queues は 100 万 ops/月込・$0.40/百万・128 KB/メッセージ・再試行 100 回。
- **Static Assets SPA**: `assets: {directory, binding, not_found_handling: "single-page-application", run_worker_first: ["/api/*","!/api/docs/*"]}` (wrangler 4.20.0+)。`run_worker_first` 無しだとブラウザのナビゲーションは Worker に届かない。
- **Next.js on Workers の公式推奨は 2026-08 から vinext (ベータ、Next 16.x のみ)**。OpenNext (`@opennextjs/cloudflare` 1.20.13) は Next 16.4 対応済 (1.20.12) だが Node Middleware (`proxy.ts`) 未対応表記、`email`/`scheduled` は custom worker で足す。
- **better-auth 1.7.12 + genericOAuth + Drizzle D1 + Hono は workerd で起動**し、discovery を要求時に取得して PKCE S256 の authorize URL を返す (実測、`nodejs_compat` 要、auth は request ごとの factory)。バンドル 373 KiB gzip。code 交換以降は未実測。Drizzle アダプタの `db.transaction` は MySQL 分岐のみ。
- **Custom Domain**: `routes:[{pattern, custom_domain:true}]`。既存 CNAME のある同名ホストには作れない。DNS 上、ワイルドカード (`*.zone` の Tunnel CNAME) は同名の完全一致レコードが無い時だけ適用されるので、Custom Domain 作成後は完全一致が勝つ (wildcard が居る名前への作成可否の明示は無く、実作成で確認が要る)。
- **Workers Builds**: token は現状ユーザー所有のみ、ビルド変数は実行時に渡らない。`wrangler-action@v4` + "Edit Cloudflare Workers" テンプレが外部 CI の標準。

## Why

Workers で完結させる場合の制約 (D1 の 2 MB 行・export 不可の FTS・128 MB メモリ) が設計を決める。

## How to apply

- 本文は R2、D1 は索引と抜粋。FTS は派生物として再構築可能にする。
- SPA + API は Hono + Static Assets の単一 Worker (email/scheduled も同居)。Next を Workers に載せるなら vinext の成熟度と OpenNext の維持状況を都度確認。
- 初回デプロイで Custom Domain の作成可否 (wildcard 共存) を確認する。
