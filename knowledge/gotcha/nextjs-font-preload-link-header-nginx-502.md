---
title: next/font の和文フォント preload で Link ヘッダが肥大し、前段 Nginx が 502 を返す
category: gotcha
project: global
tags: [nextjs, next-font, nginx, 502, link-header, coolify, cloudflare-tunnel]
created: 2026-09-16
sources: [projects/bloom-web (2026-09-16 実測), sessions/2026-09-16-d33aab8e]
---

## Context

bloom-web (Next.js 16.3.5、standalone、Coolify) を Cloudflare Tunnel → Nginx → Traefik → コンテナの経路で公開したとき、静的ページ (`/privacy` 等) は 200 なのに動的レンダリングの `/` だけ 502 になった。コンテナログにはエラーが無く、`/healthz` も 200。

## What

- `next/font/google` で `Zen_Kaku_Gothic_New({ weight: ["400","500","700"] })` を使うと、動的ページのレスポンスに **`Link: </_next/static/media/...>; rel=preload; as=font` が 49 本 (5.9 KB)** 付く (和文フォントはユニコードレンジで多数のスライスに分割され、ウェイトごとに preload される)
- レスポンスヘッダ合計 6.8 KB が Nginx の `proxy_buffer_size` (既定 4k/8k) を超え、Nginx が `upstream sent too big header` で **502** を返す。静的ページは Link ヘッダが付かないので通る
- 見分け方: `curl -sS -D - -o /dev/null http://localhost:3000/ | wc -c` が 4 KB を超えていたら疑う。`grep -ic "^Link:"` で本数を見る

## Why

Nginx は上流のレスポンスヘッダを 1 バッファで読む。Next の early-hints 用 Link は和文フォントの分割数に比例して増えるので、日本語サイトで踏みやすい。

## How to apply

- 和文フォントは `preload: false` にする (スライスは `unicode-range` で必要分だけ遅延ロードされるので体感差はほぼ無い)。欧文の可変フォント 1 つだけ preload を残す
- 直せない場合は Nginx 側で `proxy_buffer_size 16k; proxy_buffers 4 32k;` だが、appily の Nginx は共有設定なのでアプリ側で直すのが筋
- スモークで「動的ページのヘッダ合計 < 4 KB」を検査項目に入れる (bloom-web の `scripts/smoke.sh` は未対応、次回追加)
