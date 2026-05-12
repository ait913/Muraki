---
title: "Coolify on Cloudflare の 307/302 HTTPS リダイレクトループ"
category: gotcha
project: global
tags: [coolify, cloudflare, https, traefik, deploy, redirect-loop]
created: 2026-05-12
updated: 2026-05-12
sources:
  - knowledge/tool-quirk/coolify-api.md
  - Muraki/projects/tomori デプロイで実踏 (2026-05-12)
  - https://coolify.io/docs/integrations/cloudflare/tunnels/full-tls  # 公式の別解 (Tunnel + Full Strict)
  - https://github.com/coollabsio/coolify/issues/7374  # v4.0.0-beta.448 で OFF にしても redirect される open bug
  - https://community.cloudflare.com/t/possible-bug-http-redirect-loop-when-dns-is-proxied/206612
---

## Context

Coolify (`coolify.aisaba.net`) で新規 application を立てると、HTTP/2 307 or 302 で **location が自分自身** という無限リダイレクトループを起こす。Cloudflare 配下のデプロイで再現性ある。

## What

```
$ curl -I https://tomori.appily.run/
HTTP/2 307
location: https://tomori.appily.run/
server: cloudflare
```

```
$ curl -L https://tomori-api.appily.run/api/healthz
curl: (47) Maximum (50) redirects followed
```

- Coolify の `is_force_https_enabled` は **default true**
- Cloudflare 側で Always Use HTTPS / SSL Flexible だと、Cloudflare → Origin が HTTP で叩く
- Origin (Coolify Traefik) は HTTP リクエストを 307/302 で HTTPS リダイレクト
- Cloudflare 経由でクライアントに返って HTTPS で再リクエスト
- Cloudflare → Origin は再び HTTP → ループ

## Why

Coolify は単体運用前提 (Origin に直接ブラウザ接続) を default にしてる。Cloudflare のような CDN/proxy 前段の存在を想定してないので、HTTPS 強制を origin 側でやってしまう。Cloudflare 側は SSL/TLS 設定によっては HTTP で origin を叩くため、ループになる。

## How to apply

**新規 application 作成直後に、必ず `is_force_https_enabled: false` を PATCH する**。これは Cloudflare 配下の Coolify deploy における **default 手順**。

```bash
export COOLIFY_API_TOKEN="..."
APP_UUID="..."

# 新規作成直後
curl -sS -X PATCH \
  -H "Authorization: Bearer $COOLIFY_API_TOKEN" \
  -H "Content-Type: application/json" \
  "https://coolify.aisaba.net/api/v1/applications/$APP_UUID" \
  -d '{"is_force_https_enabled":false}'

# 即時反映には redeploy が必要 (PATCH だけだと proxy label が再書き込みされない)
curl -sS -H "Authorization: Bearer $COOLIFY_API_TOKEN" \
  "https://coolify.aisaba.net/api/v1/deploy?uuid=$APP_UUID&force=false"
```

## 検出方法

deploy 後の確認スクリプトに以下を入れる:

```bash
status=$(curl -sS -o /dev/null -w "%{http_code}" -I --max-time 10 "https://<domain>/<healthz-or-root>")
if [ "$status" = "307" ] || [ "$status" = "302" ]; then
  loc=$(curl -sS -I --max-time 5 "https://<domain>/" | grep -i '^location:' | tr -d '\r')
  echo "WARN: $status redirect detected — check is_force_https_enabled"
  echo "$loc"
fi
```

## 代替案 (採用しない理由)

- **Cloudflare SSL/TLS mode を Full (Strict)** に変更 — **これは Coolify 公式が推奨している解** ([Cloudflare Tunnel + Full TLS docs](https://coolify.io/docs/integrations/cloudflare/tunnels/full-tls))。Cloudflare → Origin も HTTPS にすれば redirect が成立するが、Touri の Cloudflare 設定全体を変える話で副作用大きい。app 個別の Coolify 側 patch の方が局所的で安全 — **公式とは別軸の現実解として採用**
- **Cloudflare の Always Use HTTPS を OFF** — 他のサイトと共通設定なので tomori 単体の都合で変えない
- **Coolify redirect 設定を `none`** — knowledge `tool-quirk/coolify-api.md` 既述、`"none"` は enum 外で invalid (`null` も実踏で reject)

## 既知のバグ

★ **`is_force_https_enabled=false` を PATCH しても redirect される** ことがある (v4.0.0-beta.448 で報告、open): [#7374](https://github.com/coollabsio/coolify/issues/7374)

その場合は [`gotcha/coolify-traefik-stale-label-loop.md`](./coolify-traefik-stale-label-loop.md) の復旧手順 (fqdn 削除 → redeploy → 戻し → redeploy) を試す。

## 関連

- [`tool-quirk/coolify-api.md`](../tool-quirk/coolify-api.md) — Coolify API の癖、`is_force_https_enabled` write-only など
- [`gotcha/coolify-traefik-stale-label-loop.md`](./coolify-traefik-stale-label-loop.md) — patch しても直らない時の復旧手順
- [`pattern/coolify-deploy-debug-flow.md`](../pattern/coolify-deploy-debug-flow.md) — 5層切り分けフロー
