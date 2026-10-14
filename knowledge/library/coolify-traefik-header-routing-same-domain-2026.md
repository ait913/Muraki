---
title: Coolify v4.4.6 + Traefik v3.6 で同一ドメインをリクエストヘッダで別 app に振り分ける (custom_labels / file provider)
category: library
tags: [coolify, traefik, routing, header, priority, custom-labels, appily, app-review, bloom]
created: 2026-10-15
project: global
sources:
  - https://doc.traefik.io/traefik/v3.6/reference/routing-configuration/http/routing/rules-and-priority/  # Header / HeaderRegexp, 既定 priority = rule の長さ
  - https://doc.traefik.io/traefik/v3.6/reference/install-configuration/providers/overview/  # <name>@<provider> で他 provider のオブジェクトを参照
  - https://github.com/coollabsio/coolify/blob/v4.4.6/app/Jobs/ApplicationDeploymentJob.php  # generate_compose_file: custom_labels があればそれを使う (L3914-)
  - https://github.com/coollabsio/coolify/blob/v4.4.6/app/Http/Controllers/Api/ApplicationsController.php  # domains PATCH で readonly ならラベル再生成 (L3590), APPLICATION_SETTING_FIELDS
  - https://github.com/coollabsio/coolify/blob/v4.4.6/bootstrap/helpers/proxy.php  # --providers.file.directory=/traefik/dynamic/ (L774)
---

## Context

bloom の App Store 審査用環境 (審査中の版だけ `X-Client-Version` で別 backend へ送る) の事前調査 (2026-10-15)。Appily (オンプレ Coolify 4.4.6、Traefik は coolify-proxy v3.6、前段 CF Tunnel -> Nginx :80 -> Traefik 127.0.0.1:8880) で GET のみ・ソース読みで確認。実際にルーターを張っての実測はしていない。

## What

- Coolify が生成する app のラベル (bloom-api 実機): `traefik.http.routers.http-0-<uuid>.rule=Host(...) && PathPrefix(...)`、entryPoints `http` (Nginx からは http entrypoint に入る)、service `http-0-<uuid>`。`https-0-<uuid>` も並ぶ。GET `/applications/{uuid}` の `custom_labels` に **現在のラベル全文が base64 で入っている** (null ではないことがある)
- Traefik v3: `Header(key, value)` は完全一致、`HeaderRegexp(key, re)` は Go 正規表現。**既定 priority = rule 文字列の長さ** (長い方が勝つ)。明示 `priority` の 0 は無視、上限 MaxInt64-1000。同値時の順序は docs に記載なし -> 明示 priority を付ける
- Coolify v4.4.6 の deploy は `custom_labels` が保存されていればそれをそのまま使う (`coolify.` 始まりだけ除去)。**再生成されるのは `domains` / `noindex_domains` / basic auth を API で PATCH したとき (readonly ラベル ON の場合)** と、readonly ON で `is_gzip_enabled` / `is_stripprefix_enabled` を変えたとき。→ 追加ルーターを custom_labels に足した app で domains を触ると追加分が消える
- `is_container_label_readonly_enabled` は API の設定可能フィールドに無い (UI のみ)。ただし `custom_labels` 自体は API で PATCH 可 (base64 必須)
- Coolify 既定の proxy compose は `--providers.file.directory=/traefik/dynamic/` + `watch=true` (ホスト `/data/coolify/proxy/dynamic/`)。file provider のルーターから docker 側の service を `http-0-<uuid>@docker` で参照できる (provider namespace 規則)。Appily の proxy compose は手で書き換え + chattr +i 済みなので、file provider が残っているかはサーバーで要確認
- 振り分けに使うヘッダが CF -> cloudflared -> Nginx -> Traefik を素通しすることは、bloom の版ゲート (`X-Client-Version` を見て 426) が本番で機能していることで実証済み

## Why

Traefik のルーティングは provider を跨いで priority 順に 1 つの表で評価されるので、「同じ Host + 追加条件」の長い rule を足すだけで既存ルーターより優先される。Coolify はラベルを deploy 毎に作り直さないので、custom_labels に足した行は domains を触らない限り残る。

## How to apply

1. 振り分け先 app に自分のドメイン (例 `bloom-api-review.appily.run`) を付けて普通に作る (`is_force_https_enabled=false`)
2. 次のどちらかで追加ルーターを張る
   - (A) 振り分け先 app の custom_labels に追記 (Coolify API だけで完結、ssh 不要): `traefik.http.routers.review-hdr.rule=Host(`bloom-api.appily.run`) && Header(`X-Client-Version`, `0.3.0`)` / `.entryPoints=http` / `.service=http-0-<review uuid>` / `.middlewares=gzip` / `.priority=1000` -> redeploy。外すときは行を消して redeploy
   - (B) `/data/coolify/proxy/dynamic/<name>.yaml` に file provider のルーター (service は `http-0-<uuid>@docker`)。ファイル削除で即外れる (redeploy 不要)。サーバー作業なので事前承認
3. 振り分け先の app で domains を PATCH しない (A の追加分が消える)。wasawasa は domains / custom_labels を触らない (2026-10-15 grep)
4. 確認は Traefik 直叩き: `curl -H "Host: bloom-api.appily.run" -H "X-Client-Version: 0.3.0" http://127.0.0.1:8880/healthz` と、ヘッダ無しの応答を対で比べる (両 backend で違う値を返す endpoint を使う)。外からは 404 で判定しない (`library/cloudflare-tunnel-2026.md` の罠)
5. ヘッダ振り分けは「クライアントの全経路がそのヘッダを付ける」ことが前提。WebSocket・画像/動画の GET・OS の背景転送を個別に確認する (bloom は WS と媒体 GET に版ヘッダを付けていなかった)
