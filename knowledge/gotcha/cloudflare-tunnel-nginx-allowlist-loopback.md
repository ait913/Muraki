---
title: Cloudflare Tunnel 経由は loopback 接続 — Nginx の IP allowlist に 127.0.0.1 を入れ忘れると 403
category: gotcha
tags: [cloudflare-tunnel, nginx, allowlist, loopback, 403, cloudflare_only.conf]
created: 2026-05-20
project: global
sources:
  - https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/
---

## Context

aisaba_platform の Nginx vhost には Cloudflare edge IP からのみ受け付ける allowlist が `cloudflare_only.conf` として include されている (`allow 173.245.48.0/20; ... deny all;`)。これは Cloudflare proxy 配下で「edge を経由しない直撃を弾く」目的で導入された防御策。

Cloudflare Tunnel に切替えた時、cloudflared は **同一ホストの localhost** に対して HTTP リクエストを投げる:

```
CF edge → cloudflared (origin) → http://127.0.0.1:80 → Nginx
```

ここで `cloudflare_only.conf` の deny all に**ローカル接続が引っかかって 403** になる。

## What

Tunnel 化直後にいくつかの hostname が **403 Forbidden** を返す (or Cloudflare 側で 521)。Nginx access log を見ると `127.0.0.1 - - "GET ..." 403` が並ぶ。原因は Nginx の IP allowlist が CF edge IP リストのみで loopback を含んでいないため。

## Why

`cloudflare_only.conf` は **Tunnel ではなく Cloudflare proxy (オレンジ雲) 想定の防御策**。proxy 経由なら edge IP からアクセスが来るので allowlist で守れたが、Tunnel 経由は cloudflared プロセスが origin と同一マシン上にあり、接続元 IP は `127.0.0.1` or `::1` になる。Cloudflare の Public IP リストに loopback は含まれない → 弾かれる。

## How to apply

`cloudflare_only.conf` の先頭に loopback を 2 行追加するだけで全 vhost (include してる箇所すべて) に効く:

```nginx
# Cloudflare経由のみ許可
# Tunnel (loopback) も許可
allow 127.0.0.1;
allow ::1;
allow 173.245.48.0/20;
allow 103.21.244.0/22;
# ... 残りの CF IPv4/IPv6 リスト
deny all;
```

```bash
sudo cp /var/aisaba_platform/gateway/cloudflare_only.conf{,.bak}
sudo sed -i '/^# Cloudflare経由のみ許可/a\
# Tunnel (loopback) も許可\
allow 127.0.0.1;\
allow ::1;' /var/aisaba_platform/gateway/cloudflare_only.conf
sudo nginx -t && sudo nginx -s reload
```

### 確認

```bash
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: api.aisaba.net" http://localhost/
# 200 ならOK、403 ならまだ allowlist が効いてる
```

### 派生注意点

- `set_real_ip_from` を CF edge IP リストで設定している環境では、loopback 接続では X-Real-IP が壊れる (アプリ側で `CF-Connecting-IP` ヘッダを直接読むなら問題なし)
- 自前で書いた Nginx vhost を新規追加する時、`cloudflare_only.conf` を include するか/しないかは要設計判断 (Tunnel 経路は必ず loopback、Tunnel 内 ingress で hostname 制限すれば allowlist 不要にもできる)

### 関連罠: ufw を絞ると Coolify (Docker) も巻き添えになる

Tunnel 化に伴って ufw を「LAN-only allow」(`allow from 192.168.0.0/16 to any port 51000` 等) に絞ると、**Coolify (Docker) コンテナからホストへの接続も deny される**。

ログで判定:

```bash
sudo tail -50 /var/log/ufw.log | grep "UFW BLOCK"
# SRC=10.0.x.x DST=10.0.0.1 DPT=51000 のような Docker bridge 由来の block が出る
```

Docker default の bridge subnet は実装次第:
- 素の Docker は `172.17.0.0/16`
- Coolify は独自に `10.0.0.0/24` (bridge) + `10.0.1.0/24` (coolify network) を使う

Coolify は「自サーバー validation」で**自身の sshd に SSH 接続**を試みる。これが deny されると Coolify dashboard に "You can't use this server until it is validated." と出る。

対処: Docker subnet 全体を ufw で allow:

```bash
# Coolify (10.0.0.0/16 を使う場合)
sudo ufw allow from 10.0.0.0/16 comment "Docker internal (Coolify)"

# 素の Docker の場合
sudo ufw allow from 172.17.0.0/16 comment "Docker default bridge"
```

外部からのアクセスとは無関係 (Docker 内部ネットはホスト経由でしか到達不可) なので全ポート allow しても問題なし。
