---
title: appily の通信経路と、監視・検出・遮断の現実解 (Coolify 4.4 access log / CF Access Rules / Traefik は deny 不可)
category: library
tags: [appily, coolify, traefik, cloudflare, nginx, access-log, ip-block, crowdsec, bloom, security]
created: 2026-10-10
project: global
sources:
  - https://github.com/coollabsio/coolify/blob/main/bootstrap/helpers/proxy.php  # traefikAccessLogCommands() (main, 2026-10-10 取得)
  - https://github.com/coollabsio/coolify/blob/main/app/Http/Controllers/Api/ServerSentinelController.php  # PATCH /servers/{uuid}/sentinel
  - https://coolify.io/docs/core/observability/monitoring/traffic-analytics
  - https://developers.cloudflare.com/api/resources/firewall/subresources/access_rules/methods/create/
  - https://developers.cloudflare.com/waf/tools/lists/
  - https://developers.cloudflare.com/waf/tools/ip-access-rules/
  - https://developers.cloudflare.com/waf/custom-rules/
  - https://docs.crowdsec.net/u/bouncers/cloudflare/
  - https://raw.githubusercontent.com/crowdsecurity/hub/master/parsers/s01-parse/crowdsecurity/traefik-logs.yaml
  - https://doc.traefik.io/traefik/reference/install-configuration/observability/logs-and-accesslogs/
  - https://raw.githubusercontent.com/fail2ban/fail2ban/master/config/jail.conf
model-era: sonnet-5.5
---

## Context

bloom (Go API) に「アドミンサービス」(通信監視 + 不審 IP の自動遮断) を別 Coolify app として足す設計の事前調査 (2026-10-10)。Coolify 実機 (v4.4.3、GET のみ) と実コード・ローカル Traefik v3.6 で確認した。

## What

### 通信経路 (実測 + 既存 knowledge)

```
Client -> Cloudflare edge (proxied) -> cloudflared (Tunnel, host) -> Nginx :80 (host, aisaba_platform)
       -> Traefik (coolify-proxy v3.6.13, 127.0.0.1:8880 経由) -> bloom-api :8080 (docker network "coolify")
```

- `bloom-api.appily.run` / `bloom-api-dev.appily.run` / `n-wasabi.org` はすべて CF プロキシ (A/AAAA が 104.21.x / 172.67.x、`server: cloudflare`、`cf-ray` 付き)。origin IP は露出しておらず、ufw で 80/443 は LAN のみ
- 本物のクライアント IP は **`CF-Connecting-IP`** にだけ載る (CF が上書き)。Traefik 視点の peer は Nginx、Nginx 視点の peer は 127.0.0.1 (cloudflared)。bloom の `ClientIP` (`internal/httpapi/clientip.go`) は peer が private/loopback のとき `CF-Connecting-IP` -> XFF 右端の非 trusted の順に採る
- Nginx が `CF-Connecting-IP` を落としていないかは **未確認** (ssh していない)。Nginx の `proxy_set_header` と `real_ip_header` を見るか、アクセスログを有効化した後に UA 付きで 1 発叩いて確かめる

### Coolify 4.4 の Traefik アクセスログ機能 (★設計の鍵)

- Server の `is_traffic_analytics_enabled` を true にすると、Coolify が Traefik に `--accesslog=true --accesslog.filepath=/traefik/access.log --accesslog.format=json` と、ヘッダ `Cf-Connecting-Ip` / `Cf-Ipcountry` / `X-Forwarded-For` / `User-Agent` / `Referer` / `Cf-Ray` 等の keep を付ける。ホスト側は `/data/coolify/proxy/access.log`。20MB 超で 5 世代 gz のローテーションサイドカー (`coolify-proxy-logrotate`、truncate 方式) も付く
- ★ **Appily では Coolify の Traffic analytics を ON にしない (UI でも API でも)**。proxy の `/data/coolify/proxy/docker-compose.yml` は Nginx 前段用に手で `127.0.0.1:8880:80` 等へ書き換えられ、`chattr +i` で保護されている (2026-04-17 に Coolify の startproxy が上書きして壊した経緯、`docker-compose.yml.broken-by-startproxy-20260417` が残置)。UI で ON にすると Coolify が compose を作り直そうとして `tee: ... 許可されていない操作です` で失敗する (書けていたら 80:80 に戻り Nginx と衝突して全 app 停止の恐れ)。v4.4.3 の API は `is_traffic_analytics_enabled` を受け付けない (`ALLOWED_FIELDS` 外で 422)。**2026-10-11 に手で有効化済み**: `chattr -i` → command に Coolify v4.4.3 の `traefikAccessLogCommands()` と同じ 11 フラグ (`--accesslog=true`、`filepath=/traefik/access.log`、`format=json`、headers keep = Cf-Connecting-Ip / Cf-Ipcountry / Cf-Cache-Status / Cf-Verified-Bot / Cf-Ray / X-Forwarded-For / User-Agent / Referer) を追記 → `chattr +i` → `sudo docker compose up -d` (proxy 約 16 秒断)。退避 `docker-compose.yml.before-accesslog-20261011`。ローテーションは Coolify のサイドカーの代わりに `/etc/logrotate.d/coolify-traefik-access` (daily / maxsize 20M / rotate 3 / copytruncate)。Coolify 画面の Traffic analytics は OFF 表示のまま (集計画面は使わない)。実測: `request_Cf-Connecting-Ip` に端末の実 IP (IPv6 含む) が載る = Nginx は CF-Connecting-IP を素通しする。Coolify の集計結果を読む API は無い (UI のみ)。
- ユーザー自身の `--accesslog*` フラグは analytics ON の間は管理フラグに置換され、OFF で復元される

### Traefik アクセスログ JSON (ローカル v3.6 で実測)

- `ClientHost` = peer の IP (信頼 proxy 設定なしなら Nginx 側のアドレス)。`forwardedHeaders.trustedIPs` を足すと XFF の**生文字列** (`"1.1.1.1, 9.9.9.9"`) がそのまま入る (パースされない)
- 追加ヘッダは `request_Cf-Connecting-Ip` のように **先頭大文字小文字が正規化されたキー**で出る。`DownstreamStatus` / `RequestPath` / `RouterName` / `Duration` は常に出る
- **未知ホストへの 404 (スキャナ) も 1 行ログに出る** (`RouterName` なし)。`*.appily.run` は wildcard DNS なのでスキャンの大半はここに落ち、bloom-api には届かない
- `RequestPath` は生パス。**bloom は招待トークンをログに残さない設計 (`routePattern`、§16-2) なのに、Traefik ログには `/v1/invites/{token}` 等が生で載る**。admin は取り込み時に正規化・マスクが必要

### 遮断手段の実測・調査結果

- Traefik は peer が `forwardedHeaders.trustedIPs` 外なら受信 `X-Forwarded-*` を**削除**してから peer を XFF に append する (traefik `pkg/middlewares/forwardedheaders/forwarded_header.go` の `ServeHTTP`、2026-10-29 確認)。Coolify proxy は trustedIPs 未設定なので、Traefik の背後のアプリが見る XFF は直前 hop 1 要素のみ。クライアント IP は `Cf-Connecting-Ip` を使うか trustedIPs を足す (Nexom の `TRUSTED_PROXY_COUNT` のように XFF 段数に依存するアプリは要再設計)
- Traefik `ipAllowList` は allow 専用 (deny 不可、実測: リスト外は 403)。`ClientIP(...)` ルールマッチャ + `noop@internal` + 403 を返す middleware の組は **peer アドレスにしか効かず XFF/CF ヘッダは見ない** (実測: trustedIPs 設定下でも `X-Forwarded-For: 9.9.9.9` は素通り、peer を含めると 403)。つまり Nginx が前段にいる本構成では Traefik 層での本物の IP deny は実用にならない (forwardAuth で自前判定する経路は残るが、全リクエストに 1 ホップ足し、落ちたら全断 or fail-open の選択になる)
- Cloudflare IP Access Rules: 全プラン 50,000 件/アカウント、アカウントレベルは**全 zone に効く**。mode は block / challenge / managed_challenge / whitelist など。`ip_range` は IPv4 が **/16 と /24 のみ**、IPv6 が **/32 /48 /64**。必要権限は `Account Firewall Access Rules Write`。**TTL 機能は無い** (admin が rule id を持って期限で DELETE する)。ネイティブアプリ (JS 不可) には challenge は意味がなく block のみ実用
- CF WAF Custom Rules は Free で 5 本。カスタム IP List は Free で **1 リスト / 10,000 件**
- CF Logpush (HTTP requests) は Free では使えない。公式 docs の可用性表は曖昧で、使えないとするのは第三者ドキュメントのみ (**未確認**)。GraphQL Analytics は `httpRequestsAdaptiveGroups` / `firewallEventsAdaptive` が全プランで 31 日以上保持、クエリ上限は 5 分 300 回。Free 固有の maxDuration は docs から取れず未確認 (zone の `settings` ノードを叩けば確定)
- **CrowdSec**: (1) `traefik-logs` parser の source_ip は `ClientHost` の末尾要素で `CF-Connecting-IP` を使わない -> Nginx 配下では全部 Nginx/loopback になり、private レンジはデフォルトで whitelist されるので何も検出されない。(2) CF bouncer は Workers + KV 方式で、**zone に A/AAAA レコードが必須 (CNAME のみの zone は除外せよと明記)**。`*.appily.run` は tunnel への CNAME のみ。Free は KV 書き込み 1,000/日、Worker 100K req/日。(3) Traefik bouncer plugin は stream mode、plugin は CLI フラグだけでは有効化できず (静的設定 `experimental.plugins` が要る)、IP 取得は XFF/指定ヘッダ依存
- fail2ban 既定値 (閾値の相場): `maxretry=5`, `findtime=10m`, `bantime=10m`、`bantime.increment` は既定 off (有効化すると前科ごとに倍々)

### bloom 側の既存ログの制約

- `access` ログには **IP が無い**。`rate_limited` も `ip_hash` (日次ローテーションの HMAC)。意図的なプライバシー設計。401 には `auth_reason` / 未検証 `auth_sub` があるが IP と結べない
- lat/lng/cell 等は `ConfigureLogger` で `[redacted]`。位置は admin に流さない前提で、「物理的にあり得ない移動」は **bloom-api が自分で判定して座標を含まない event (user_id, kind, speed) だけ出す** のが筋

## Why

アドミンは bloom-api の外から見えるものだけで判定するなら、IP を持つ層 (Traefik/Nginx/CF) のログしか使えない。その層で deny を打てるのは CF のみ (Traefik は deny 不可、CrowdSec は IP 帰属が崩れ CF bouncer は CNAME zone 非対応)。よって「検出は Traefik の JSON アクセスログ、遮断は CF IP Access Rules (+ アプリ層 deny)」が最短の整合ルートになる。

## How to apply

- 設計では、データ源 = Coolify の traffic analytics を ON にして `/data/coolify/proxy/access.log` を admin が read-only の**単一ファイル bind mount** で読む (ディレクトリ丸ごとは `acme.json` と動的設定が見えるので避ける。truncate ローテーションなので inode は変わらない)。ON にすると proxy が再起動する点を計画に入れる (01:00 JST の自動再起動の直後などを狙う)
- 遮断 = CF IP Access Rules を admin が作る (TTL は admin 側で管理して期限切れ DELETE、IPv6 は /64、IPv4 は単一 IP。/24 は CGNAT 巻き込みが怖いので自動では打たない)。allowlist 必須: 自宅/Touri、App Store 審査、Coolify/cloudflared (loopback)、CF の IP レンジ
- 検出入力に使う IP は `request_Cf-Connecting-Ip` のみ。無ければ判定しない (peer が private のとき自動遮断しない)
- 取り込み前に Traefik ログの `RequestPath` を正規化 (invite token 等をマスク)、保持期間を決める (IP は個人情報。プライバシーポリシーとの整合を Touri に確認)
