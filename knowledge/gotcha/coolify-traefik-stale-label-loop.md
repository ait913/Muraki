---
title: Coolify で全パス self-redirect ループになる時の復旧手順
category: gotcha
tags: [coolify, traefik, deploy, redirect-loop]
created: 2026-05-10
updated: 2026-05-12
project: global
sources:
  - https://github.com/coollabsio/coolify/blob/main/bootstrap/helpers/docker.php
  - https://github.com/coollabsio/coolify/issues/7374  # Force HTTPS OFF でも redirect (open)
  - https://github.com/coollabsio/coolify/issues/6877  # malformed Traefik labels
  - https://github.com/coollabsio/coolify/issues/6545  # stripprefix middleware 誤適用 → ループ
  - https://github.com/coollabsio/coolify/issues/6495  # Traefik 静的 config が勝手に reset
  - https://github.com/coollabsio/coolify/issues/6599  # Generate Domain → Save で label 消失
  - https://github.com/coollabsio/coolify/issues/6233  # loadbalancer port label 欠落
---

## Context

Coolify (Traefik) で Dockerfile アプリをデプロイ。`fqdn` 個別指定 (例 `https://meishilink.appily.run`) + server に `wildcard_domain=https://appily.run` 設定済の構成。

ビルドもコンテナ起動も成功し、Next.js が `Ready in 379ms` まで出てるのに、外部から HTTPS でアクセスすると **全パスが** `301`/`302` で **`Location: <自分自身>`** を返すループ。`/foo` のような存在しないパスも同様。

Coolify が生成する Traefik label をソースで追っても (`bootstrap/helpers/docker.php` の `fqdnLabelsForTraefik`)、`redirect=both` のときに self-redirect middleware は付かないはず。理論上は出ないルーティング状態。

## What

復旧手順 (順に試す):

1. **`is_force_https_enabled` を false に**: Coolify の default は **true**。これが ON だと HTTP entrypoint に `redirect-to-https` middleware が付く。stale な dynamic config と組み合わさると HTTPS リクエストにも誤適用される疑いあり
2. **fqdn を一旦削除 → 戻して force redeploy**: PATCH `/applications/{uuid}` で `domains` を空にする → redeploy → 戻す → redeploy。これで Coolify が Traefik dynamic config をクリーンアップ・再生成する。今回はこれで 200 復帰
3. **`redirect` を `both` に**: `non-www` / `www` だと、`host` が一致しない条件でループに巻き込まれることがある。`both` は middleware を一切追加しない安全側

切り分けの仕方:

- `fqdn=null` で deploy → 当該ドメインが **404** に変わる = 「Coolify routing 自体がループ source」が確定 (Cloudflare ではない)
- `fqdn` 戻して 200 → 解決
- 戻して再ループ → label の生成パターンに恒久的なバグ。`custom_labels` で完全 override (base64 string) するか、別 fqdn 文字列で試す

## Why

Coolify の Traefik dynamic config は `/data/coolify/proxy/dynamic/` 配下で file provider 経由で配布。アプリ設定変更時に **古い label set がクリアされず stale state で残ることがある** (公式 issue 多数)。fqdn 削除→戻しで強制再生成。

`is_force_https_enabled=true` の場合、Coolify は HTTP routers にだけ `redirect-to-https` middleware を付ける設計だが、stale state や middleware の重複適用で HTTPS 経路も巻き込むケースがある。

Cloudflare (orange cloud) 経由でも、Origin (Coolify Traefik) が出した 301 をそのまま透過するので `server: cloudflare` ヘッダだけ見て Cloudflare のせいと決めつけない。**Origin と Cloudflare の切り分けは fqdn 削除実験**が手早い。

## How to apply

新規 Coolify Dockerfile アプリで全パス self-redirect ループを観測したら:

```sh
# 1) is_force_https_enabled を false
curl -X PATCH -H "Authorization: Bearer $COOLIFY_API_TOKEN" \
  $COOLIFY_API_BASE/applications/<uuid> \
  -d '{"is_force_https_enabled":false,"redirect":"both"}'

# 2) fqdn 一旦削除 → redeploy で 404 確認
curl -X PATCH ... -d '{"domains":""}'
curl "$COOLIFY_API_BASE/deploy?uuid=<uuid>&force=true"
# → 当該ドメインが 404 になれば Origin が原因 (Cloudflare 無罪)

# 3) fqdn 戻して redeploy
curl -X PATCH ... -d '{"domains":"https://<original>"}'
curl "$COOLIFY_API_BASE/deploy?uuid=<uuid>&force=true"
# → 200 になれば解決
```

それでも直らなければ Coolify UI で **Server → Proxy → Restart** (API endpoint なし)。最終手段は SSH で `coolify-proxy` コンテナを `docker restart`。

## 関連 known issues (2026-05 時点 open)

このループの根本原因は単一バグではなく、Coolify Traefik label 生成系の複数バグの総体:

- [#7374](https://github.com/coollabsio/coolify/issues/7374): `is_force_https_enabled=false` を設定しても redirect される (v4.0.0-beta.448)
- [#6877](https://github.com/coollabsio/coolify/issues/6877): malformed Traefik labels (`Host()` `&& PathPrefix...` のような構文崩れ)
- [#6545](https://github.com/coollabsio/coolify/issues/6545): stripprefix middleware の誤適用で無限ループ
- [#6495](https://github.com/coollabsio/coolify/issues/6495): Traefik 静的 config が勝手に reset される
- [#6599](https://github.com/coollabsio/coolify/issues/6599): Generate Domain ボタン → Save で label が消える
- [#6233](https://github.com/coollabsio/coolify/issues/6233): loadbalancer port label が欠落

新規詰まり時はこれらの open issue を grep して既知パターンか確認すると無駄な調査を回避できる。**不明なら Coolify GitHub issue を直接検索**: <https://github.com/coollabsio/coolify/issues?q=is%3Aissue+traefik+redirect>

## 関連

- [`gotcha/coolify-https-redirect-loop.md`](./coolify-https-redirect-loop.md) — Cloudflare 配下の `is_force_https_enabled` ループ (本書の上位症状)
- [`tool-quirk/coolify-api.md`](../tool-quirk/coolify-api.md) — API の癖、`custom_labels` base64 強制等
- [`pattern/coolify-deploy-debug-flow.md`](../pattern/coolify-deploy-debug-flow.md) — 5層切り分けフロー
