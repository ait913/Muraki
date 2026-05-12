---
title: Coolify アプリのデプロイ詰まり調査フロー
category: pattern
tags: [coolify, debug, deploy, troubleshooting]
created: 2026-05-10
updated: 2026-05-12
project: global
sources:
  - knowledge/tool-quirk/coolify-api.md
  - knowledge/gotcha/coolify-https-redirect-loop.md
  - knowledge/gotcha/coolify-traefik-stale-label-loop.md
  - https://raw.githubusercontent.com/coollabsio/coolify/main/openapi.yaml
---

> 不明な API 挙動が出たら Coolify 公式 docs / OpenAPI を必ず参照: <https://coolify.io/docs/api-reference>, <https://raw.githubusercontent.com/coollabsio/coolify/main/openapi.yaml>

## Context

Coolify でデプロイしてアプリが想定通りアクセス可能にならないとき、原因が「ビルド」「コンテナ起動」「環境変数」「Traefik routing」「Cloudflare proxy」のどこにあるか切り分けるパターン。MeishiLink のデプロイで体系化。

## What

5 層の段階的切り分け:

### 層1: ビルド完了したか
```sh
curl -H "Authorization: Bearer $TOKEN" \
  $BASE/deployments/applications/<uuid> | jq '.deployments[0:3] | .[] | {deployment_uuid, status, commit, created_at}'
```
最新 deployment の status を確認:
- `failed` → ビルドログを `.deployments[0].logs` から取得 (二重 JSON encoded、Python で parse 推奨)
- `finished` → 層2 へ

### 層2: コンテナが起動して安定してるか
```sh
curl ... $BASE/applications/<uuid> | jq '{status, restart_count, last_restart_type, last_online_at}'
```
- `restart_count > 0` + `last_restart_type=crash` → クラッシュループ。層3 へ
- `running:healthy` or `running:unknown` → 層4 へ

### 層3: 起動時クラッシュの理由 (race-catch)
コンテナ logs API は running 中しか返さないので、再起動の隙間でレースキャッチ:
```sh
curl ... $BASE/applications/<uuid>/restart
for i in $(seq 1 30); do
  resp=$(curl ... $BASE/applications/<uuid>/logs?lines=200)
  if echo "$resp" | grep -q '"logs"'; then
    echo "$resp" | python3 -c "import json,sys,re; raw=sys.stdin.read(); m=re.search(r'\"logs\"\\s*:\\s*\"(.+)\"\\s*}\\s*$', raw, re.DOTALL); s=m.group(1) if m else raw; s=bytes(s,'utf-8').decode('unicode_escape', errors='replace'); s=re.sub(r'\\x1b\\[[0-9;]*[mK]','',s); print(s[-3000:])"
    break
  fi
  sleep 1
done
```
典型的な原因:
- env 未設定 (`AUTH_SECRET` / `DATABASE_URL` 等) → 1 件ずつなら `POST /applications/<uuid>/envs`、複数件なら `PATCH /applications/<uuid>/envs/bulk` で一括登録
- DB 接続文字列エラー → schema.prisma の `datasource` 設定確認
- ライブラリ依存欠落 (`MODULE_NOT_FOUND`) → Dockerfile runner stage の COPY 範囲不足

### 層4: HTTP がアクセスできるか
```sh
curl -o /dev/null -w "%{http_code}|%{redirect_url}\n" https://<fqdn>/
curl -o /dev/null -w "%{http_code}\n" https://<fqdn>/foo  # 存在しないパスで 404 返るか
```
- 200 / 想定 redirect → 完了
- 全パス self-redirect (Location: <self>) → 層5 (Traefik routing 問題)
- 404 → fqdn 設定確認、または container がリクエストを受けてない
- ★ **PATCH 時に 409 Conflict が返ってきた場合は他アプリと domain 衝突**。`tool-quirk/coolify-api.md` の domain conflict 節へ。`?force_domain_override=true` で奪取できるが破壊操作なのでユーザー承認必須

### 層5: Origin (Coolify Traefik) か Cloudflare か切り分け
```sh
# fqdn を一旦削除 → 当該ドメインの応答を見る
curl -X PATCH ... $BASE/applications/<uuid> -d '{"domains":""}'
curl ... "$BASE/deploy?uuid=<uuid>&force=true"
# 結果:
# - 404 になる → Origin (Coolify routing) が原因。Cloudflare 無罪
# - 同じ self-redirect 続く → Cloudflare 側に Page Rule / Bulk Redirect / Always Use HTTPS 設定がある可能性
```

→ Cloudflare 確認は **ユーザーの Cloudflare Dashboard** でしかできない (API token がない限り)。Origin が原因なら `gotcha/coolify-traefik-stale-label-loop.md` の復旧手順 へ。

## Why

Coolify は層が多くて、詰まりがどこにあるか log だけだと分かりづらい。**「Origin か Cloudflare か」の切り分けに fqdn 削除実験が一番早い**。Cloudflare bypass curl は appily.run のような Cloudflare proxy 隠蔽ドメインだと Origin IP に届かないので、fqdn 削除側から攻める方が確実。

## How to apply

新規 Coolify デプロイで詰まったら、層1→層5 を順に。1層ずつ判定して原因の存在範囲を狭める。各層で curl one-liner があるので、順次実行できる。

層3 の race-catch は **クラッシュループでログ取得不可状態の必殺技**。次回も使う。
