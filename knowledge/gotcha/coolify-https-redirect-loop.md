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

### ★ この PATCH は必要だが十分ではない (2026-07-16 omatase で実証)

**`is_force_https_enabled:false` を初回デプロイ前に PATCH しても、ループは起きる。**

omatase で新規 app 2 つ (`omatase-api` / `omatase-web`) を `instant_deploy:false` で作成 → **一度もデプロイする前に** force_https を PATCH → 初回デプロイ、という「教科書通り」の順序を踏んだが、**両方とも 302 self-redirect ループになった**。再 PATCH (`redirect:"both"` 併記) + `force=true` redeploy でも直らず、**fqdn 削除 → redeploy → 復元 → redeploy** で初めて 200 になった (両 app とも)。

★ **この事例は「stale label」では説明がつかない**: 新規作成した app は過去に別の fqdn/設定でデプロイされたことが無く、クリアされるべき古い label が**そもそも存在しない**。それでもループした。つまり `gotcha/coolify-traefik-stale-label-loop.md` の Why (「古い label set が残る」) は**この症状の一部しか説明していない**。根本原因は未特定。

**実務上の結論**: Cloudflare 配下で新規 app を立てるときは、**fqdn 削除 → redeploy → 復元 → redeploy を「復旧手順」ではなく「新規作成フローの一部」として最初から見込む**。作成直後の PATCH だけで 200 が返ると期待しない。

### ★ ただし「fqdn を変更したとき」には踏まなかった (2026-07-16, n=1)

同じ omatase の 2 app に対し、後日 `domains` を PATCH して**別ドメインを追加** (`omatase.appily.run` → `omatase.n-wasabi.org,omatase.appily.run`) → `force=true` redeploy したときは、**両 app とも一発で 200**。ループは出なかった。

つまり現時点の観測は:

| 操作 | ループ |
|---|---|
| **app の新規作成** → 初回デプロイ | **踏んだ (2/2)** |
| 既存 app の **fqdn 変更** → redeploy | **踏まなかった (2/2)** |

**n=1 の事例なので「fqdn 変更なら安全」と一般化しないこと。** 言えるのは「新規作成時は高確率で踏む」だけ。fqdn を触ったら毎回プローブして確認する運用は変えない。

```bash
# 新規 app の 200 が返らないとき、再 PATCH を繰り返さず即座にこれをやる (再 PATCH は効かなかった)
curl -X PATCH ... -d '{"domains":""}'                                  # fqdn 削除
curl "$COOLIFY_API_BASE/deploy?uuid=$APP_UUID&force=true"              # → 404 を確認 (Origin が犯人 = Cloudflare 無罪の切り分けも兼ねる)
curl -X PATCH ... -d '{"domains":"https://<original>","is_force_https_enabled":false}'
curl "$COOLIFY_API_BASE/deploy?uuid=$APP_UUID&force=true"              # → 200
```

デプロイ完了時に `GET /applications` の `status` が **`running:healthy` なのに外部が 302** なら、コンテナは無罪で Traefik 層の問題と即断してよい (omatase では両 app とも healthy のまま 302 だった)。

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
