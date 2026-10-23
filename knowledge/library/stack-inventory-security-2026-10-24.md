---
title: 技術スタック全量棚卸しとセキュリティ状況 (2026-10-24) — Pillow 13 の 39 件が Python 3.10 を詰ませている
category: library
tags: [security, inventory, cve, pillow, python, cockpit, traefik, dompurify, maplibre, coolify, node, go, postgresql]
created: 2026-10-24
project: global
sources:
  - Muraki/projects/*/ のマニフェスト・lockfile (2026-10-24 時点の作業ツリー。bloom のみ origin/master b75db96)
  - Coolify API GET /applications, /databases, /version (2026-10-24 実測)
  - https://api.osv.dev/v1/querybatch (全 lockfile の推移依存を一括照会) / https://api.osv.dev/v1/vulns/<id>
  - https://github.com/advisories/GHSA-jrc7-96c5-q579
  - https://pypi.org/pypi/Pillow/json
  - https://nodejs.org/en/blog/vulnerability/october-2026-security-releases
  - https://www.postgresql.org/support/security/
  - https://nginx.org/en/security_advisories.html
  - https://github.com/traefik/traefik/security/advisories
  - https://github.com/cockpit-project/cockpit/security/advisories
  - https://endoflife.date/api/python.json
---

## Context
2026-10-22 の第 1 回棚卸し ([[coolify-stack-security-floors-2026-10]]、session 2026-10-22-acd89e01) の 2 日後。Dependabot が omatase と maplibre-gl を報告したのを機に、全 PJ をマニフェストから数え直し、10-15 以降の advisory を OSV (全 lockfile の推移依存) と GitHub Advisory / ベンダーページで照合した。

**このファイルが置換するもの**: coolify-stack-security-floors の「Coolify 4.4.7 最新」(→ 4.5.0 が 10-23 に出て稼働中)、Python 依存の下限 `Pillow>=12.3.0` ([[python-web-deps-cve-floors-2026]]、→ 下記 ★1 で不足)。それ以外の事実 (Node 20 EOL、eMudhra、postgis タグ凍結、npm 下限) はそちらが正で、ここには重複させない。

**読み方**: 版は「作業ツリーの lockfile」。稼働コンテナの実版 (`docker exec`) は 10-22 以降取れていない (ホストへ ssh しない条件)。「到達性」は静的に読んだ判断で、実機 PoC はしていない。

## What

### ★ 要対応 (CRITICAL / HIGH)

| # | 対象 | 内容 | 影響範囲・到達性 | 対応 |
|---|---|---|---|---|
| ★1 | aisaba_platform / Nexom の Pillow 12.3.0 (Python 3.10 venv) | **2026-10-20〜22 に Pillow の GHSA が 39 件公開 (CRITICAL 4 / HIGH 23 / MODERATE 12)、全て 13.0.0 (10-16 公開、`requires_python >=3.11`) でのみ修正**。12.x に backport 無し (PyPI 最新 12.3.0 = 07-01)。CRITICAL: GHSA-8g5g (JPEG draft 経由ヒープ溢れ)、GHSA-332p (TIFF 書込)、GHSA-v9pv (multi-frame の stale storage)、GHSA-w889 (EPS の Ghostscript 引数注入 = RCE) | Nexom は `formats=[JPEG,PNG,GIF,WEBP]` + 画素数上限 + `convert/resize` のみ (`draft()`/`thumbnail()` 不使用) なので、メモリ破壊系 (TIFF/EPS/MPO/draft) は**静的には到達しない見込み**。ただし GIF/PNG の DoS 系 (GHSA-74r2 GIF コメント二次、GHSA-65qm GIF seek、GHSA-5xm2 APNG、GHSA-g4qv PNG eXIf 二次) は許可フォーマット内で到達しうる (アップロード API) | Python ≥3.11 の venv (24.04 の 3.12 / uv / deadsnakes) に載せて `Pillow>=13`。Nexom の pyproject と aisaba requirements の `<13` を外す。Touri 裁定「Ubuntu 24.04 はまだ」(10-23) と衝突するので**エスカレーション対象**。つなぎ策: 受付フォーマットを JPEG/PNG/WEBP に絞る (GIF/APNG を外す) |
| ★2 | ホストの cockpit (console.aisaba.net で nginx 経由公開) | GHSA-m4gv (CVE-2026-4631, **CRITICAL** 未認証 RCE、SSH 引数注入、GitHub 表記の範囲「> 326」→ 360 で修正)。GHSA-6jmq (CVE-2026-4802, HIGH 8.0、細工リンクでログページ RCE、「> 240」→ 362 で修正、要ユーザー操作)。Ubuntu の tracker は jammy / noble とも "Needs evaluation" (修正版なし) | **ホストの cockpit 版は未確認** (jammy 標準は 264、jammy-backports は 360)。264 なら m4gv の範囲外だが 6jmq の範囲内。console.aisaba.net は 10-19/20/22 に実利用あり | Leader: `dpkg -l cockpit*` と console.aisaba.net の前段認証 (Cloudflare Access 等) の有無を確認。不要なら停止 (cockpit.socket) が最安 |
| 3 | wasawasa の dompurify 3.4.16 (mermaid 12.1.0 経由) | GHSA-cg2g (CRITICAL 表記、10-22)、GHSA-mrv2 (HIGH)、GHSA-c6gr (LOW) → 3.4.17 で修正 | GHSA 本文は `SAFE_FOR_TEMPLATES` + DOM 返却モードの**非既定設定**が前提。mermaid 側がその設定で呼ぶかは未確認。クライアント側のみ・Org 内部ユーザー限定 | `pnpm update dompurify` (mermaid の依存範囲 `^3.4.12` で解決可、mermaid 自体は上げなくてよい) → 通常デプロイ |
| 4 | Coolify の proxy (Traefik、10-22 時点 3.6.13、現行は**未確認**) | 10-07〜10-21 に **HIGH 10 件** (ForwardAuth/FastProxy の NTLM・Negotiate 接続プール汚染、snicheck の `:scheme http` 迂回、FastProxy の data race で全体 panic、k8s ingress-nginx 系)。修正は **3.7.14〜3.7.16 のみ**。3.6 系の最終は 3.6.25 (07-31) で 10 月分の修正を含まない。最新 3.7.16 | この構成 (CF Tunnel → nginx :80 → Traefik、Docker provider、TLS は CF 終端、ForwardAuth/NTLM/k8s 不使用) では**到達しにくい**。FastProxy は experimental の opt-in | Leader 判断で Coolify の Proxy 設定から v3.7 系へ。急ぎではない。実版は `docker ps` で確認要 |
| 5 | atender-api の axios 1.16.1 / follow-redirects 1.16.0 (node-ical 0.20.1 経由) | axios: HIGH 7 + MODERATE 14 (9/30 と 7/20 公開、1.20.0 で修正)、follow-redirects HIGH 2 (10-20、1.16.1 で修正)、uuid 10 / moment 2.30.1 が MODERATE | **到達しない**: atender は `ical.parseICS(text)` のみで、axios を呼ぶ `fromURL` は使っていない (`apps/api/src/lib/icsParse.ts`) | 緊急性なし。次の依存更新で `pnpm.overrides` (axios>=1.20.0 / follow-redirects>=1.16.1)。node-ical 0.27.3 は axios を捨てているが API 変更あり |
| 6 | atender-web の seroval 1.5.4 (TanStack Router 経由) | GHSA-p6vx (CRITICAL 表記、10-05、1.6.2 で修正)、GHSA-jp82 (HIGH、1.6.3) | SPA (SSR なし) でサーバー生成 JSON を `fromJSON` する経路が無いため**到達しない見込み** (未実測) | 次の依存更新で `@tanstack/router-core` を上げて seroval ≥1.6.3 |
| 7 | onikeiri-api (Touri の WIP ブランチ `feature/v1-foundation` b8068aa が Coolify に載っている) | hono 4.13.0 に MODERATE 5 (hono/jsx の XSS、serveStatic の二重デコード等)、@hono/node-server 2.0.2 に MODERATE 2 | 本番稼働中の API。jsx / serveStatic を使っているかは未確認 | hono ≥4.13.13、@hono/node-server ≥2.1.5 に上げて再ビルド (他 PJ は 10-22 に更新済) |
| 8 | omatase (**サービス停止済、記録のみ**) | maplibre-gl 6.0.0 に **GHSA-jrc7-96c5-q579 (CVE-2026-85061, CRITICAL, 08-19 公開)**: `DOM.sanitize()` の attribution XSS。≤6.4.0 → **6.4.1** (最新 6.15.0)。他に shell-quote 1.10.0 CRITICAL (1.11.0)、xmldom / brace-expansion / js-yaml 等の HIGH 多数 (Expo・Next のビルド時依存) | 停止中。再開するなら maplibre-gl ≥6.4.1 (`^6` なので `pnpm update maplibre-gl` で届く) | 対応なし (PJ 停止)。再開時に上記 |

### maplibre は他にあるか
- **bloom (iOS)**: Flutter `maplibre_gl` 0.27.1 → iOS 側は **MapLibre Native 6.28.0** (`maplibre-gl-native-distribution`、SPM)。これは JS ライブラリ `maplibre-gl` とは別物で、GHSA-jrc7 の対象外。MapLibre Native / distribution 側の GitHub Advisory は 0 件 (Advisory DB + repo の security-advisories で確認)。`maplibre_gl_web` は pubspec.lock に推移依存として入るが Bloom は iOS 専用で Web ビルドしない
- **bloom/mocks** (`m2`, `m3-live` の HTML モック): CDN から `maplibre-gl@4.7.1` を読む。範囲内 (≤6.4.0) だが、開発用モック / Artifact 用で本番配信物ではない。attribution に外部文字列を入れていないので影響なし。モックを触る機会があれば CDN の版を 6.4.1 以上に
- wasawasa / ais-pass / atender / kinketsu / bloom-web / agent-hub / dandan に maplibre は無い (package.json / pubspec / go.mod を grep)

### MEDIUM-LOW・対応は更新のついで

| 対象 | 内容 | 到達性 | 対応 |
|---|---|---|---|
| dandan-app (Go) | x/text 0.37.0: GO-2026-5970 (無限ループ)・GO-2026-6629 (precis の panic)。修正 0.41.0 | pgx の SCRAM が `x/text/secure/precis` を通る。入力は自前の DB パスワードのみ → 低 (govulncheck は未実行) | `go get golang.org/x/text@latest` で次回デプロイに |
| bloom-server (Go) | GO-2026-5932: `x/crypto/openpgp` は非推奨 (修正なし) | openpgp を import していない (grep 0 件) | 対応なし |
| bloom-web | source-map-js 1.2.1 HIGH (DoS、1.2.2) | Next / PostCSS のビルド時のみ | 次の `pnpm update` で |
| kinketsu | @vitest/mocker 4.1.11 MODERATE 2 (4.1.12)、esbuild 0.18.20 (drizzle-kit 経由) | テスト / dev サーバーのみ | 次の更新で |
| ais-pass | 推移依存を含め advisory 0 件 | — | なし |
| bloom (Flutter) | pubspec.lock 193 パッケージで OSV 0 件。Dio の GHSA-cr65 (10-15) は `dio_http2_adapter` の話で未使用 | — | なし |
| Postgres コンテナ | 最新 16.15 / 17.11 / 18.6 (08-10〜13、27 CVE、CVSS 8.8 が 8 件。大半は任意 SQL 実行権限が前提)。次回リリースは四半期慣例で 2026-11-12 のはず (14 系は同日 EOL、公式予告は未確認)。10-22 時点の実機は 17.9〜17.11 / 16.13・16.14 が混在 | アプリ用ロールのみ・外部非公開 (ufw) → 低〜中 | **現在の実版は未確認**。Leader: `SELECT version()` を各 DB で。古ければ DB コンテナを再作成 (イメージ再 pull) |
| certifi | agent-hub は 2026.10.19、最新は 2026.10.23 | advisory ではなく CA 更新 | 次回ビルドで |

### 解消済み・要対応なし
- **Next.js**: 稼働中の ais-pass / wasawasa / bloom-web は 16.4.2 で 10-22 の 3 advisory (GHSA-673q / 2464 / p3m5) の修正済み。16.4.3 (10-23) は不具合修正のみで security ではない。GHSA-h694 (cache leak、10-22) は 16.3.0〜16.3.7 のみで対象外。golden-hour-emergency は 15.5.14 のままだが**未デプロイ** (Coolify に無い)
- **React 19.3.1 / 19.2.9** (10-14) は RSC 系修正だが Next 同梱 runtime で吸収済み (10-22 確認済)
- **Node**: 10-21 以降の新 security release は無い (22.23.4 / 24.22.1 / 26.12.1)。Node 26 は 10-27 から Active LTS
- **Go**: 1.27.3 / 1.26.10 が最新で、`stdlib` の OSV は両方 0 件
- **ホスト**: nginx 1.30.6 (stable の 10 月修正含む)、cloudflared 2026.10.3、Docker Engine 29.9.2 (moby の 10-01 advisory GHSA-7cfq / 6m9p は 29.8.2 で修正済)、Coolify **4.5.0 が稼働中** (API 実測、10-23 リリース。4.5.0 に PHP 系サービステンプレートの CVE-2026-109618/109619 対応と平文秘密の at-rest 暗号化を含む)。Coolify 本体の GHSA は 07-02 公開分が最新で、4.5.0 以降の新規なし
- **Python (agent-hub、10-22 版)**: PyJWT 2.15.1 / mcp 1.30.0 / cryptography 50.0.2 / anyio 4.15.1 / starlette 1.9.0 / uvicorn 0.54.0 / httpx 0.28.1 / asyncpg 0.32.0 / jinja2 3.1.6 すべて最新で OSV 0 件。`mcp` は 2.x が出ているが `<2` 固定の方針通り
- **aisaba venv (gunicorn 26.2.0 / multipart 2.0.1)**: 最新で OSV 0 件 (Pillow だけが★1)。fastapi / Markdown / markdown2 / requests / urllib3 / bs4 の最新版も 0 件だが、**稼働 venv の実版は未確認**
- **iOS**: Firebase iOS SDK 12.19.0 (最新 13.1.1)、GoogleSignIn-iOS 9.2.0 とも GitHub Advisory 0 件 (Swift エコシステム照会)。Flutter は手元 3.47.0、stable 最新 3.47.7 (10-08)。Flutter / Dart SDK の新規 advisory なし (Dart pub の zip slip 低、02-23 のみ)

### 棚卸し: 現役 (Coolify 実測 2026-10-24 + マニフェスト)

| PJ | Runtime / ベース | Framework・主要 lib (lockfile 版) | DB・ホスティング | 状態 |
|---|---|---|---|---|
| ais-pass | Node 24-alpine、pnpm 9.15 | Next 16.4.2 / React 19.3.0 / better-auth 1.7.12 + oauth-provider / drizzle 0.45.3 / pg 8.23.1 / otpauth 9.5.2 / Tailwind 4.3.3 | postgres:17-alpine、`pass.aisaba.net` (nginx → Traefik 8880)。Phase 3 (Workers + R2/D1、Cloudflare Email) は設計前で未デプロイ | 稼働 healthy |
| wasawasa | Node 24-alpine | Next 16.4.2 / React 19.3.0 / better-auth 1.7.12 / @modelcontextprotocol/server 2.3.1 / drizzle 0.45.3 / tiptap 3.31.4 / mermaid 12.1.0 (dompurify 3.4.16 ★3) / yjs 13.6.33 | postgres:17-alpine、wasawasa.n-wasabi.org | 稼働 healthy |
| bloom (api/admin) | Go 1.27.3 (ビルド `golang:1-alpine` → `alpine:3`)、go.mod 1.26.4 | pgx 5.10.0 / golang-jwt 5.3.1 / coder/websocket 1.8.15 / golang-migrate 4.19.1 / x/net 0.60.0 / x/crypto 0.57.0 | postgres:17-alpine。prod + dev1 (master) + dev2/dev3 (version/0.2.5)、review 環境 2 つは exited。bloom-netlog は `version/0.2.1.1` の Go | 稼働 |
| bloom (iOS) | Flutter 3.47.0 / Dart 3.13、app 0.2.4+37 | maplibre_gl 0.27.1 (MapLibre Native 6.28.0)、firebase_core 4.15.0 (SDK 12.19.0)、crashlytics 5.4.0、drift 2.34.3、sqlite3 ^3.5、dio 5.11.0、sign_in_with_apple 8.1.0、riverpod 3.4.2 | App Store / TestFlight | 公開中 |
| bloom-web | Node 22-alpine | Next 16.4.2 / React 19.3.0 / sharp 0.35.5 | bloom.n-wasabi.org | 稼働 healthy |
| atender | api: Node 22-alpine。web: Vite でビルド → nginx:alpine。`.nvmrc` の 20 は手元用で古い | api: Hono 4.13.13 / @hono/node-server 2.1.5 / better-auth 1.6.33 / Prisma 6.19.3 / better-sqlite3 11.10.0 / resend 6.12.3 / node-ical 0.20.1。web: Vite 6.4.2 / React 19.2.6 / TanStack Router 1.169.2 | SQLite (Volume)、atender(-api).appily.run。iOS は SwiftUI + GoogleSignIn-iOS 9.2.0 (Expo ではない) | 稼働 (App Store 審査提出済) |
| kinketsu-taisaku | Node 22-alpine | Hono 4.13.13 / better-auth 1.6.33 / drizzle 0.45.4 / better-sqlite3 12.10.0 / nodemailer 10.1.7 / React 19.2.7 / Vite 8.3.5 | SQLite、kinketsu-taisaku.appily.run | 稼働 |
| agent-hub | python:3.12-slim (3.12.15) | mcp 1.30.0 (<2) / starlette / uvicorn / asyncpg / PyJWT 2.15.1 / cryptography 50.0.2 | postgres:16-alpine、agent-hub.appily.run | 稼働 |
| dandan-app | Go 1.26.10、distroless/static-debian12 | MCP go-sdk 1.6.1 / pgx 5.10.0 / goose 3.27.2 / x/text 0.37.0 (MEDIUM-LOW) | postgres:17-alpine、dandan.appily.run | 稼働 |
| onikeiri-api | Node 22-alpine | Hono 4.13.0 / node-server 2.0.2 / better-auth ^1.6.26 / drizzle 0.45 / pg 8 (★7) | postgres:17-alpine、onikeiri.appily.run。`ait913/oni-keiri` の WIP ブランチ `feature/v1-foundation` | 稼働 (開発中) |
| nwasabi-hp | nginx:1.31-alpine | 静的 | n-wasabi.org | 稼働 healthy |
| aisaba-platform + nexom | Python 3.10.12 (Ubuntu 22.04 の python3.10、共有 venv 1 本) | Nexom 1.2.0 / gunicorn 26.2.0 / multipart 2.0.1 / Pillow 12.3.0 (★1) / Appera (TS) | ホスト上の systemd `nexom@*` ×7 (nginx ← cloudflared)。FastAPI の `aisaba_main` は別 venv (`/ais/service/api/aisaba/venv`、版未確認) | 稼働 |
| cybozu_hands-on | nginx 静的 | — | cybozu-hands-on.appily.run (`ait913/cybozu_hands-on`、Muraki 管理外) | 稼働 |

### 棚卸し: 停止・終了・未デプロイ

| PJ | 状態 | 根拠 |
|---|---|---|
| omatase | **一時クローズ (2026-10-24)**。Coolify の omatase-api / omatase-web が exited (omatase-pg は running:healthy のまま) | omatase/CLAUDE.md、Coolify API。Next 16.4.2 / React 19.2.4 / maplibre-gl 6.0.0、Expo 57.0.8 / RN 0.86.0、Go 1.26.10 + gorilla/websocket 1.5.3 + pgx 5.10.0 |
| meishilink / tomori / tsunagu | **終了 (2026-10-22)**。Coolify の app / DB を削除済 (Coolify API の一覧に無いことを今日も確認)。退避は `Muraki/.tmp/retired-20261022/` | sessions/2026-10-22-acd89e01 項 16。**3 PJ の CLAUDE.md に終了の記載は無い** (要更新) |
| golden-hour-emergency | 未デプロイ (Coolify に無い)。Next 15.5.14 / Node 20 のまま、deps に CRITICAL 3 + HIGH 多数 | 動かさない前提なら放置可。動かすなら全面更新 |
| dandan-mcp | 天野氏のローカル stdio 版 (Go 1.26.4、go-sdk 1.6.1)。デプロイなし | go.mod、origin = n-wasabi/dandan-mcp |
| oni-keiri (main ブランチ) | main には CLAUDE.md のみ。コードは `feature/v1-foundation` (上の onikeiri-api) | — |
| warikan | Coolify に残る exited の app (`ait913/warikan`)。Muraki 管理外 | Coolify API |
| bloom review 環境 | bloom-api-review / bloom-admin-review / bloom-pg-review が exited | Coolify API |
| postgresql-database-d10bq… | postgres:16-alpine。参照元不明のまま残置 (10-22 項 16) | Coolify API |

### 棚卸し: ホスト (aiserver2、knowledge と Coolify API のみ。ssh していない)

| 項目 | 版・状態 | 出典 / 確認度 |
|---|---|---|
| OS | Ubuntu 22.04.5 (jammy)、kernel 5.15.0-198。standard support は 2027-06-01 | [[aisaba-host-ubuntu-jammy-state-2026-10]] (10-22 実測) |
| Docker | docker-ce 29.9.2 (最新)、毎晩 01:00 に OS 再起動 | 同上 |
| Coolify | **4.5.0** (API 実測)。proxy = Traefik (版は未確認、10-22 は 3.6.13 ★4) | API / 10-22 |
| nginx | 1.30.6 (nginx.org stable)、:80 のみ公開 | 10-22 |
| cloudflared | 2026.10.3 | 10-22 |
| ホスト Node | nodesource 22.x (22.23.4) | 10-22 |
| cockpit / code-server | cockpit :9090 (console.aisaba.net で使用中)、code-server :8080 (0.0.0.0 bind、ufw で閉鎖)。**版は未確認** (cockpit ★2、code-server 最新 4.141.0、既知 GHSA は 2025-05 のみ) | knowledge |
| 削除済み | apache2 / php8.1 / mysql / samba / vsftpd / shellinabox / telnet / openjdk-17 / lxd 等 (10-23) | 同上 |
| apt パッケージ (openssl / glibc / kernel の USN) | **未確認** | — |

## Why
- 「ビルド時に最新を pull」も「下限を最新に固定」も、**依存の最新版が Python/Node のランタイム要件で止まる**と効かない。Pillow は 13.0.0 (>=3.11) でしか直らないのに、本番は Ubuntu 22.04 の 3.10 に縛られている。10-21 の下限決定 (12.3.0) はその時点では正しかったが、10-20〜22 の 39 件で陳腐化した
- OSV の lockfile 一括照会は件数が出すぎる (atender 94 件、golden-hour 100 件超)。peer 依存の辺 (`peerDependencies` に載る名前) を除いた prod 閉包で絞らないと dev 専用 (vitest / tinypool / better-auth CLI) の CRITICAL が本番扱いになる
- GitHub の severity ラベルは到達性を見ない (dompurify の CRITICAL は非既定設定前提、axios 群は呼ばないコードパス)。表の「到達性」列が判断の本体

## How to apply
- 優先順: ★1 (Pillow、要 Touri 判断) → ★2 (cockpit の版確認) → 3 (dompurify、機械的) → 7 (onikeiri の hono) → 4 (Traefik 3.7)
- Pillow の恒久策を決める時は、Python 3.11+ をどう載せるか (24.04 化 / uv で venv だけ) が論点。`requirements.txt` の `pillow>=12.3.0,<13` と Nexom `pyproject.toml` の `Pillow>=12.3.0` を同時に置換する (追記しない)
- lockfile の一括 OSV 照会は `POST /v1/querybatch` (500 件ずつ) → `GET /v1/vulns/<id>` で `database_specific.severity` と `affected[].ranges[].events[].fixed` を取る。pnpm-lock は `snapshots` を辿り、`packages.<key>.peerDependencies` の名前の辺を捨てると prod 閉包が実態に近い
- 次回の棚卸しで最初に取るべき実機値: `docker exec` の Node/Go 版、各 DB の `SELECT version()`、Traefik の版、`dpkg -l cockpit*`、aisaba の各 venv の `pip freeze`
