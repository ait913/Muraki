---
title: Cloudflare Tunnel 1 本でオンプレ全公開 (HTTPS + SSH, 2026年5月構成)
category: library
tags: [cloudflare-tunnel, cloudflared, nginx, dns, ssh, access-policy, aisaba.net, appily.run, ceez7.com]
created: 2026-05-20
project: global
sources:
  - https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/
  - https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/origin-parameters/
  - https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/use-cases/ssh/ssh-cloudflared-authentication/
---

## Context

オンプレ Ubuntu サーバー (`192.168.3.17`、SoftBank光) で運用している全サブドメイン (aisaba.net / appily.run / ceez7.com / SSH) を Cloudflare Tunnel 1 本に統一した時の構成。グローバル IP 変動でアクセス不能になる事故を機に、全通信を Tunnel に乗せ、ポート転送と外向きの listen を全廃した。

## What — 確定した最終構成

### サーバー側

- **cloudflared**: Ubuntu 22.04 jammy、apt `pkg.cloudflare.com` 経由インストール、systemd `cloudflared.service`
- **Tunnel 名**: `aisaba-home` (UUID は `~/.cloudflared/<UUID>.json` で発行)
- **設定**: Local-managed (`config.yml` を `/etc/cloudflared/` に置く)
- **ingress**: 2 ルール
  - `deaoifarisuvbesias.aisaba.net` → `ssh://localhost:51000`
  - catch-all → `http://localhost:80` (Nginx)
- **Nginx**: 全 vhost を `listen 80` に統一、`ssl_certificate*` 行は全削除、`/ais/ssl/*.pem` は `/ais/ssl.bak-pre-tunnel/` に退避
- **Cloudflare Origin Cert は廃棄**。CF edge ↔ origin の暗号化は Tunnel が担う
- **ufw**: 80/51000 は LAN (`192.168.0.0/16`) のみ、443 は完全閉。default deny

### DNS (Cloudflare 側)

zone ごとに wildcard CNAME + apex CNAME (flatten) で最少エントリ:

| zone | レコード |
|---|---|
| aisaba.net | `aisaba.net` CNAME, `*.aisaba.net` CNAME (両方 proxied) |
| appily.run | `*.appily.run` CNAME (apex は使わない) |
| ceez7.com | `ceez7.com` CNAME, `*.ceez7.com` CNAME |

全部 `<tunnel-uuid>.cfargotunnel.com` に向ける。SSL/TLS mode は Full (Strict)。MX/TXT/DKIM は別途残す。

### Access (SSH 用)

- **Self-hosted Application**: `deaoifarisuvbesias.aisaba.net`
- **Policy**: Allow, Include Emails: `touri1705@outlook.com`
- **Identity provider**: One-time PIN (Zero Trust → Integrations → Identity providers で有効化)

### クライアント (Mac)

```sshconfig
Host aisaba
  HostName deaoifarisuvbesias.aisaba.net
  User ais
  ProxyCommand /opt/homebrew/bin/cloudflared access ssh --hostname %h
```

初回 `ssh aisaba` で `cloudflared access` が Cloudflare Access のブラウザ認証を要求。token は 24h キャッシュ。SCP/SFTP/rsync/VSCode Remote SSH も透過動作。

## Why — 設計判断の理由

### 「Nginx 無変更で `https://localhost:443` に流す」を**やめた**

最初は Nginx を触らない方針 (cloudflared → `https://localhost:443` + `noTLSVerify`+`matchSNItoHost`) で疎通確認まで成功。だが「Origin Cert が冗長に残る」「Touri 設計哲学 (ミニマル/明示的) に反する」ため即 80 化に移行。**Nginx 20+ vhost の `listen 443 ssl` → `listen 80` + `ssl_*` 行削除は sed 一発**で済むので、443 残留より 80 統一の方がコスト安。

- アプリケーション側コード (URL hardcode 等) は**書換不要**。CF edge は HTTPS で公開し続けるので外向き URL は変わらない。書換わるのは Tunnel↔Nginx の内部 1 ホップだけ
- 80 化後の cloudflared ingress は `service: http://localhost:80` 一本、`originRequest` 不要

### wildcard CNAME を使うメリット (Appily 運用が楽になる)

`*.appily.run` 1 個 CNAME → 新規アプリを Coolify で立てるたびに DNS 個別追加が**不要**になる。Coolify Traefik (`127.0.0.1:8880` で listen、Nginx が proxy_pass) がサブドメインベースで振り分ける。

### Cloudflare `is_force_https_enabled=false` は Tunnel 化しても継続必要

Tunnel 経由でも CF edge は HTTPS 終端 → cloudflared → Nginx は HTTP。Coolify アプリ側で HTTPS リダイレクトを返すと **307 ループ**になる構造は不変。`[[coolify-https-redirect-loop]]` の根因は Tunnel 化で解消しない。

### SSH の `cloudflared access ssh` ProxyCommand 方式 + Access policy

公式が SSH ingress を「`cloudflared access ssh` + Access policy 前提」で設計しているため、Access 無しの SSH 公開は推奨外。Touri の email を 1 個 allow するだけで OK。ブラウザベース SSH (Access for Infrastructure) も同一 Tunnel で併用可能だが、CLI を維持したいので ProxyCommand 方式を採用。

### ufw を LAN-only にする (ルーター port forward はそのまま)

Touri 指示: 「ルーターはいいから、ファイアーウォールだけ閉めて」= サーバー側 ufw で external block。Tunnel が outbound only で動くため、80/443/51000 を inbound block しても Tunnel 経路は無影響。LAN 内からのデバッグアクセス (`ssh ais@192.168.3.17 -p 51000` や `curl http://localhost`) は維持。

## How to apply

### 新規ホスト追加 (Coolify アプリ追加時)

wildcard CNAME のおかげで DNS 操作不要:
1. Coolify で新規アプリ作成 (`is_force_https_enabled=false` 必須、`[[appily SKILL]]` の標準フロー)
2. `*.appily.run` wildcard で吸収、即アクセス可能

### 既存サービス用に固有ホスト追加 (例: `aisaba.net` 配下の新サブドメイン)

`*.aisaba.net` wildcard で吸収。Nginx に新 vhost (`listen 80; server_name foo.aisaba.net;` + `proxy_pass`) を追加するだけ。DNS は不要。

### 特殊ルート (TCP/RDP/その他 protocol) を Tunnel に追加

`/etc/cloudflared/config.yml` の `ingress:` 先頭に追加 (catch-all より前):

```yaml
ingress:
  - hostname: rdp.aisaba.net
    service: rdp://localhost:3389
  - hostname: deaoifarisuvbesias.aisaba.net
    service: ssh://localhost:51000
  - service: http://localhost:80
```

`sudo cloudflared --config /etc/cloudflared/config.yml tunnel ingress validate` → `sudo systemctl restart cloudflared`。SSH と同じく Access policy をかけるのが標準。

### トラブルシューティング

- **521 Web Server Is Down**: cloudflared が origin に届かない。`systemctl status cloudflared`、`journalctl -u cloudflared`、ingress validate を確認
- **403 Forbidden (Nginx `cloudflare_only.conf`)**: Tunnel 経由は loopback 接続。`[[cloudflare-tunnel-nginx-allowlist-loopback]]` に対処
- **CNAME 作成失敗 (`-f` でも `An A/AAAA/CNAME record already exists`)**: apex の場合、`cloudflared tunnel route dns -f` でも上書きできない。API 経由で先に既存 A を DELETE してから CNAME 作成
- **`cloudflared tunnel login` が 1 zone しか cert に入らない**: `[[cloudflared-tunnel-login-multi-zone]]`。CF API token (Edit zone DNS) で操作する方が確実

### 関連 SKILL / knowledge

- `[[appily]]` SKILL — Coolify HTTP API 経由でアプリ操作
- `[[cf-tunnel]]` SKILL — Tunnel + DNS の運用操作 (本構成用)
- `[[coolify-https-redirect-loop]]` — Force HTTPS off の必要性
- `[[cloudflare-tunnel-nginx-allowlist-loopback]]` — Nginx 側 IP allowlist の loopback 追加
- `[[cloudflared-tunnel-login-multi-zone]]` — login が 1 zone 限定の罠
