---
title: Proxmox 4VM 分割 + Coolify 複数サーバー + Cloudflare + Grafana Cloud 監視の事前調査 (2026-10-29)
category: library
tags: [proxmox, coolify, cloudflare-access, cloudflare-tunnel, grafana-cloud, alloy, auditd, laurel, crowdsec, restic, r2]
created: 2026-10-29
project: global
sources:
  - https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso
  - https://pve.proxmox.com/wiki/Roadmap
  - https://pve.proxmox.com/pve-docs/chapter-pve-firewall.html
  - https://pve.proxmox.com/wiki/Install_Proxmox_VE_on_Debian_13_Trixie
  - https://coolify.io/docs/knowledge-base/server/build-server
  - https://coolify.io/docs/knowledge-base/server/non-root-user
  - https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/validating-json/
  - https://grafana.com/pricing/
  - https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.journal/
model-era: sonnet-5.5
---

## Context

自宅 aiserver2 (D552 / i3-4170 2C4T / DDR3 16GB 増設不可 / SSD 1 本) を Proxmox VE で 4 VM (AIS Pass / Coolify 管理 / アプリ本番 / 開発) に分割する設計の事前調査。Touri 方針: セキュリティ > 性能 > 開発体験、ログは Grafana Cloud + Slack。実測済みの環境は調べず、外部仕様のみ。2026-10-29 に一次ソースを直読み。

## What

### A. Proxmox VE

- **最新安定は 9.2** (x86 ISO 9.2-1, 2026-05-21、Debian 13 Trixie、kernel 7.0。arm64 版は 2026-08-05)。10 の言及なし。https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso , https://pve.proxmox.com/wiki/Roadmap
- **要件**: 最小は RAM 1GB + ゲイン分 (評価用)、本番推奨は host 用 2GB + ゲスト分、VT-x 必須。ZFS は「最低 8GB」、ARC 既定は物理メモリの 10% (上限 16GiB)、手動で `zfs_arc_max` 調整可。**GPU/nested は不要**。i3-4170 (VT-x あり) は要件を満たす。https://pve.proxmox.com/wiki/System_Requirements , https://pve.proxmox.com/wiki/ZFS_on_Linux 。2C4T に 4 VM は vCPU 過剰割当になる (公式の数値根拠なし、設計側の見積もり事項)
- **インストール**: 公式 ISO はディスクを使う前提 (全消去の明記は今回取れず「ISO インストーラ = サポート経路」まで)。**既存 OS の上に乗せる公式手順は Debian 13 のみ** (`proxmox-default-kernel` + `proxmox-ve`、Debian カーネルは削除)。**Ubuntu 上は公式ページに記載なし = 未サポート扱い** (「不可」と明記した一次ソースは未確認)。Secure Boot + Debian 上インストールは注意事項あり。https://pve.proxmox.com/wiki/Install_Proxmox_VE_on_Debian_13_Trixie
- **単一 SSD**: PVE の標準レイアウトは ext4 root + LVM-thin (VM ディスク用。thin はスナップショット可) (https://pve.proxmox.com/pve-docs/chapter-sysadmin.html)。ZFS は RAM を食い、公式は「コンシューマ SSD は非推奨 / PLP 付き推奨」。単一 SSD・16GB・コンシューマ品なら **ext4 + LVM-thin が素直** (ZFS にすると 16GB から ARC + 計 8GB 目安を引かれる: これは設計側の推論)
- **Proxmox Firewall**: cluster.fw / host.fw / `<VMID>.fw` の 3 階層 (+ SDN VNet の forward 専用)。**既定は無効**。有効化は「Datacenter で enable」+「**各 VM の NIC ごとに firewall フラグ**」の両方が必要。VM レベルは in/out のみ。security group は cluster.fw に `[group name]` で定義、VM から `GROUP name` で参照。macfilter 既定 1 / ipfilter / ndp 既定 1 / dhcp 既定 0。公式は iptables ベースのファイアウォールが「VM 間の完全分離」を与えると記述。https://pve.proxmox.com/pve-docs/chapter-pve-firewall.html
- ★ **nftables 版 (proxmox-firewall) は 9.2 時点でも tech preview・「本番非推奨」** (Roadmap にも変化なし)。iptables 版の Linux bridge では各 VM に `fwbrX` が作られる (nftables 版は作られない)。デフォルト policy_in/out の値は option 一覧に書かれておらず**実機の Datacenter→Firewall→Options で確認が必要** (自分の記憶は in=DROP/out=ACCEPT だが一次ソース未確認)。VNet レベルの forward ルールと REJECT 禁止(DROP になる)は nftables 版の制約
- **VM 間通信を同一 bridge でも遮断できるか**: 公式の明文は「VM 間の完全分離」のみで、「同一 bridge の VM 間が in/out ルールで止まる」を直接書いた段落は今回取れず。仕様上は NIC ごとの IN/OUT が効くはず (未実機確認) → 設計時に 2 VM で `ping` / `nc` の実測を受入テストに入れる
- **ネットワーク構成案** (推論): 最小は「vmbr0 1 本 + 全 VM NIC に firewall=1 + Datacenter policy_in/out=DROP + security group で必要経路だけ許可」。別 bridge/VLAN は VM 間を L2 で割れるが、ルータ役 (OPNsense 等) が要り 16GB では重い。SDN VNet は forward ルールが nftables 版 (tech preview) 必須 → 避ける
- **Web UI 8006**: HTTPS 自己署名。cloudflared の ingress は `noTLSVerify: true` もしくは `caPool` に証明書指定 + `originServerName` (https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/origin-parameters/)。cloudflared を**ホスト上に置くべきか別 VM か**を断定する一次ソースは無い (設計判断)。ホストに置くと管理面が VM 侵害から隔離される利点 (ホストが cloudflared に侵害されるリスクと相殺)
- **バックアップ**: vzdump のターゲットは **PBS または file-level storage (dir/NFS/CIFS)**。S3 へ直接は出せない (https://pve.proxmox.com/pve-docs/chapter-vzdump.html)。S3 外出しは「dir に vzdump → restic/rclone」。**PBS は S3 datastore を持つ** (要 HTTPS、ローカルキャッシュ 64〜128GiB 推奨、「tech preview」表記は取れず未確認)。PBS は別マシン必須とは書かれていない (同一ホストの VM に置くのは推奨されない: 同一故障ドメイン、これは推論)。https://pbs.proxmox.com/docs/storage.html
- **更新**: no-subscription リポジトリは公式が「本番非推奨」と明記 (サブスクなしの現実解)。更新は `apt` / GUI、毎日チェックして root@pam にメール通知。unattended-upgrades の推奨記述は無し。カーネル更新後は再起動が要る。https://pve.proxmox.com/wiki/Package_Repositories 。**VM の onboot / startup order は設定できる** (ホスト再起動で VM を自動起動する用、docs 個別確認は未実施)

### B. Coolify 複数サーバー

- **接続要件**: SSH、root か sudo ユーザー。サーバー検証が Docker Engine / Compose を確認・インストールする (Docker を再起動することがある → 新規機推奨)。最小要件 2 core / 2GB / 10GB。Linux のみ、amd64/arm64。https://coolify.io/docs/knowledge-base/server/introduction , https://coolify.io/docs/get-started/installation
- **非 root ユーザー**: 実験的機能。パスワード無し sudo 必須 (`sudo -n whoami` が root)、アカウントはロック不可、鍵はパスフレーズ無し、`/data/coolify` を所有。**結局 root 相当**なので権限制限にはならない。https://coolify.io/docs/knowledge-base/server/non-root-user
- **Build Server**: 公式機能あり。**ビルド専用機 (アプリ/DB は載せられない)** で、レジストリ (ghcr 等) が必須、同一 CPU アーキ。**Docker Compose アプリでは使えない**。複数ビルドサーバーはランダム選択。Team 設定の「Build server fallback」を OFF にするとデプロイ機でビルドしない。アプリ側に「Docker Image」の指定が必須。https://coolify.io/docs/knowledge-base/server/build-server
- **Coolify 本体の最小要件**: 2 core / 2GB RAM / 10GB 空き (上記)
- **侵害時の被害範囲**: 公式ドキュメントに明記は無いが、Coolify は秘密鍵 (APP_KEY で暗号化して DB 保存) で各デプロイ先に root(sudo) SSH する。= Coolify VM 侵害で全デプロイ先 root。緩和: Coolify VM を Cloudflare Access で塞ぐ・Proxmox FW で Coolify VM から出る経路を SSH/22 のみに絞る・デプロイ先は Coolify VM の IP からのみ SSH 許可。公式の権限最小化手段は無い
- **Sentinel**: 新規サーバーでは既定 ON、既存は OFF のままのこともある。Metrics は別トグルで既定 OFF。必須ではない。https://coolify.io/docs/core/observability/monitoring/sentinel
- **Coolify DB バックアップ**: Settings > Backup で定期 (既定 毎日 0:00)、**S3 互換への送出に対応** (失敗時はローカル保持 + 警告)。**APP_KEY は DB バックアップに含まれない** (`/data/coolify/source/.env`)。別途保管必須。https://coolify.io/docs/knowledge-base/how-to/backup-restore-coolify
- **サーバー移動**: 公式の「サーバー間移動」は無い。Resource Operations の **Clone Resource** は別サーバー/destination に停止状態でコピー (storage の中身は未コピー、DB クローンはバックアップではない)。「Move」はプロジェクト/環境間のみ。→ 実質は再作成 + データ移行。https://coolify.io/docs/applications/operations/resource-operations 。第三者は Destination 変更 + 再デプロイと説明 (非公式、未検証)
- 追加の運用事実: 複数サーバーのリモート proxy 種別 (Traefik/Caddy) はプライマリと揃える。永続ストレージ付きアプリは複数サーバー配置不可。https://coolify.io/docs/knowledge-base/server/multiple-servers 。Coolify 4.0.0-beta.464 未満は clone に cross-tenant の CVE (CVE-2026-34037) → 現行 4.5.0 は影響外

### C. Cloudflare

- **Tunnel 数**: アカウント当たり cloudflared tunnel 1,000 本 (全プラン共通の既定値)。VM ごとに別 Tunnel は問題なし。Access apps 500、**Service token 50 個/アカウント**。https://developers.cloudflare.com/cloudflare-one/account-limits/ 。Zero Trust Free は 50 ユーザー (第三者要約。公式の plans ページを直接は未確認)
- **同一ホスト名の複数 Tunnel**: 1 つの CNAME は 1 tunnel しか指せない。複数ホスト名→同じ tunnel は可。https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/routing-to-tunnel/dns/ 。ワイルドカードを 1 Tunnel に向けている現行構成は、VM ごとの Tunnel 分割時に **ホスト名ごとの CNAME 割当に変える必要** がある (既存 knowledge/library/cloudflare-tunnel-2026.md と同じ制約)
- **Access JWT 検証**: ヘッダ `Cf-Access-Jwt-Assertion` を読む (Cookie より推奨)。鍵は `https://<team>.cloudflareaccess.com/cdn-cgi/access/certs`、`aud` = Application Audience (AUD) tag、`iss` = `https://<team>.cloudflareaccess.com`、RS256。**鍵は約 6 週ごとにローテ、旧鍵は 7 日有効 → ランタイム取得し `kid` で `public_certs` を引く**(`public_cert` 単体に頼らない)。Go は公式例が `github.com/coreos/go-oidc/v3/oidc` (RemoteKeySet + ClientID=AUD)。https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/validating-json/
- **SSH の方式**: 公式は 4 択を並べるのみで「推奨」は明記なし。(1) client-side cloudflared (現行方式、Tunnel + Access のみ、WARP 不要) (2) **Access for Infrastructure** (短命証明書 + コマンドログ。要 Cloudflare One Client + Gateway、SSH のみ、Unix ユーザーは事前作成、セッション既定 24h、"All plans" 表記だが Free での可否は未確認) (3) 自己管理鍵 + Gateway (4) ブラウザ SSH。https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/use-cases/ssh/ , https://developers.cloudflare.com/cloudflare-one/access-controls/applications/non-http/infrastructure-apps/
- **Service Token**: ヘッダ `CF-Access-Client-Id` + `CF-Access-Client-Secret` を両方送る。Access ポリシーの action は **Service Auth** (でないと IdP ログインに飛ぶ)。作成時に期間指定 (例 8760h=1年、最大値は docs に記載なし)。ローテで ID 据え置き・新 secret 発行、旧 secret の猶予 1 時間〜30 日。2026-08-26 以降発行は `cfast_` 接頭辞 + checksum。https://developers.cloudflare.com/cloudflare-one/access-controls/service-credentials/service-tokens/
- **Access ログ**: API `GET /accounts/{id}/access/logs/access_requests` (権限 Access: Audit Logs Read、`since`/`until`/`limit`/`direction`) で pull 可。ただしページに「per-request ログは Enterprise」の記述もあり**プラン制約は曖昧**。Logpush は docs 上「全プランで利用可」(2026-10 時点の docs。以前の既存 knowledge は Free の HTTP requests Logpush を使えないとしていたが、一次ソースで断定できず**未確認**。実アカウントで job 作成を試すのが決着手段)。Logpush の宛先として Grafana Cloud Loki を直接指せるかは未確認 → pull 型 (cron で API→Alloy `loki.source.file`/`loki.source.api`) が現実解。https://developers.cloudflare.com/cloudflare-one/insights/logs/audit-logs/ , https://developers.cloudflare.com/logs/logpush/
- **WAF Free**: Custom rules 5 本 (Log 以外のアクション)、Rate Limiting は **1 ルール / IP 単位のみ / 10 秒窓 / 10 秒ミティゲーション / path と Verified Bot のみ**。https://developers.cloudflare.com/waf/custom-rules/ , https://developers.cloudflare.com/waf/rate-limiting-rules/ 。カスタム IP List は 1 リスト 10,000 件、IP Access Rules 50,000 件 (既存 knowledge/library/appily-edge-monitoring-and-blocking-2026.md)

### D. Grafana Cloud + Alloy

- **Free 上限** (pricing ページ、2026-10): **ログ 50GB/月・保持 14 日**、メトリクス 10k active series・保持 14 日、Grafana 可視化ユーザー 3 人、traces/profiles 各 50GB。Pro は $19/月 + 従量 (ログ保持 30 日)。Alerting/Slack は pricing ページに記載なし、Slack contact point に**プラン制約の記載は無い**(configure-slack ページ)。https://grafana.com/pricing/
- **Alloy 導入**: apt リポジトリ `https://apt.grafana.com stable main`、鍵 `/etc/apt/keyrings/grafana.asc`、`apt-get install alloy`、サービス名 `alloy`。設定 `/etc/alloy/config.alloy`、環境ファイル `/etc/default/alloy`、`systemctl reload|restart alloy`、既定 `--storage.path=/var/lib/alloy/data`。https://grafana.com/docs/alloy/latest/set-up/install/linux/ , https://grafana.com/docs/alloy/latest/configure/linux/ 。Debian (Proxmox ホスト) でも同じ apt が使えるはず (Trixie での明示確認は未実施)
- **journald**: `loki.source.journal` (`matches="_SYSTEMD_UNIT=ssh.service"` 等、OR は不可、`relabel_rules` で `__journal__systemd_unit`→`unit`)。**alloy ユーザーを `adm` と `systemd-journal` グループへ入れないと無音で 0 行**。https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.journal/
- **Docker**: `discovery.docker` + `loki.source.docker` (host=`unix:///var/run/docker.sock`)。ソケット権限は docs に記載なし → docker グループ = root 同等の権限を Alloy に渡す点を設計で明示すること。https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.docker/
- **二重 JSON**: `loki.source.docker` は Docker API 経由なので json-file ラッパーは付かない(docs で明記はなく、API 経由の仕様から推論 → 実測要)。`loki.source.file` で `/var/lib/docker/containers/*/*-json.log` を読む場合は `stage.docker` でラッパー(`log`,`stream`,`time`)を剥がす。アプリ側 JSON は `stage.json`。https://grafana.com/docs/alloy/latest/reference/components/loki/loki.process/
- **loki.write**: `url=https://logs-xxx.grafana.net/loki/api/v1/push`、`basic_auth` の username=Loki のユーザー ID、password=Grafana Cloud の access policy トークン (logs:write)。WAL は experimental (`stability.level=experimental` が必要)。429 はリトライ。https://grafana.com/docs/alloy/latest/reference/components/loki/loki.write/
- **アラート**: Loki へのアラートは LogQL (`sum(count_over_time({...} |= "Failed password" [5m])) > N`)。推奨は Grafana-managed alert rule。Slack: Incoming Webhook か Bot token (`chat:write.public`) で contact point を作る (チャンネルごとに別 contact point)。ブロックレイアウトのカスタムは不可。https://grafana.com/docs/loki/latest/alert/ , https://grafana.com/docs/grafana/latest/alerting/configure-notifications/manage-contact-points/integrations/configure-slack/
- **ラベル設計**: Free は active streams 5,000 / ログ取り込み 5MB/s 等のデフォルト。ラベルは unit/host/vm/container 程度に抑え、IP や user はラベルにせず本文に残す(`stage.pack` もある)。https://grafana.com/docs/grafana-cloud/cost-management-and-billing/understand-your-invoice/usage-limits/

### E. auditd / CrowdSec

- **auditd JSON**: 本体は非 JSON。**LAUREL** (threathunters-io/laurel、v0.8.2 が最新タグ) が audisp プラグインとして enrich 済み JSON を出す。インストールは `/usr/local/sbin/laurel`、ユーザー `_laurel`、`/etc/laurel/config.toml`、`/etc/audit/plugins.d/laurel.conf` (auditd 3)、`pkill -HUP auditd`。Rust ビルドか release の tarball。出力先パスは README に明記なし → 実機の config.toml で確認 (**未確認**)。https://raw.githubusercontent.com/threathunters-io/laurel/master/INSTALL.md
- **ルールセット**: Neo23x0/auditd の `audit.rules`。先頭の `-i` でロード失敗を無視する (厳格に試すには `-i` を除いたコピーを `auditctl -R`)、`auid>=1000` は `UID_MIN` と整合を確認。ノイズ源は execve/execveat・socket 作成・ファイル削除・32bit ABI → Docker ホストでは環境に合わせて削る(公式推奨)。インストール先パスは README から取れず**未確認**。https://github.com/Neo23x0/auditd
- **CrowdSec と CF Tunnel**: 既存知見が詳しい → `knowledge/library/appily-edge-monitoring-and-blocking-2026.md`。要点: Traefik/Nginx に届く実クライアント IP は `CF-Connecting-IP` のみ。Traefik は同ヘッダをネイティブで読まない (プラグインか Nginx `real_ip_header` が要る)。CrowdSec の traefik-logs parser は `ClientHost` を使う。CF 側遮断は (a) Worker bouncer = 有償 Workers 推奨 / KV 制約 + zone に A/AAAA 必須 (b) IP Access Rules を API で作る。Free は WAF custom 5 本 / リスト 1 つ。Worker bouncer の有償推奨は https://app.crowdsec.net/hub/author/crowdsecurity/remediation-components/cs-cloudflare-worker-bouncer
- 起点が Tunnel (origin IP 非露出) なら、origin への直アクセス経路を作らないことが `CF-Connecting-IP` 信頼の前提 (偽装防止)

### F. オフサイトバックアップ

- **restic**: S3 互換は `restic -r s3:https://<account>.r2.cloudflarestorage.com/<bucket>` + `AWS_ACCESS_KEY_ID/SECRET` (R2 は restic docs に記載なし、S3 API として動く想定 = 一次ソース未確認)。B2 は公式が **S3 API 経由を推奨** (native B2 backend はエラー処理に難ありと記載)。パスワードで暗号化、紛失=復旧不能。rclone backend も可 (`rclone:<remote>:<path>`)。https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html
- **整合検証**: `restic check --read-data-subset 10%` (または `n/t` で 5 日で全体) で一部ずつ読む。restore 専用の検証コマンドは無い → 定期的に `restic restore` を実際に流して diff/ `pg_restore --list` する cron を別途組む。https://restic.readthedocs.io/en/stable/045_working_with_repos.html
- **R2**: Free 10GB-month 保管 + Class A 100 万 / Class B 1000 万 リクエスト、egress 無料、超過 $0.015/GB-月。API token は Object Read & Write をバケット単位で絞れる(オブジェクト delete のみ分離する設定は docs に無し)。**Bucket Lock** で prefix 単位の保持期間を設定できるが restic の `forget --prune` は削除するので衝突の可能性(推論、要検証)。https://developers.cloudflare.com/r2/pricing/ , https://developers.cloudflare.com/r2/api/tokens/ , https://developers.cloudflare.com/r2/buckets/bucket-locks/
- 10GB を vzdump の VM イメージで超えるのは現実的 (4 VM)。VM バックアップは容量の見積もりが先決(B2 は課金あり)。DB dump(小さい)を R2、VM 全体は別手段 (例: 外付け USB + 暗号化)に分ける設計が妥当 (推論)

## Why

設計の前提 (Ubuntu 上に Proxmox を乗せられるか、Proxmox FW の nftables 版は本番可か、Coolify の権限モデル、Free tier の枠) が実は違うと設計をやり直すことになる。ここは設計前に潰した事実。

## How to apply

- ★ Proxmox は **ISO で新規インストール (Ubuntu 22.04 を消去)**。Ubuntu 上乗せは公式手順なし。移行時に既存の Coolify / app 25 / PG 11 の退避・再構築計画が必須
- ★ Proxmox FW は **iptables 版 (既定) を使い、nftables 版 (tech preview) は避ける**。Datacenter policy を DROP にし、VM NIC ごとに firewall=1。VM 間遮断の実測テストを受入条件に入れる
- ★ Coolify の Build Server は **Compose アプリに効かない** + レジストリ必須。ビルド専用 VM は 16GB 環境では高コスト → 同居ビルド (現状) か外部レジストリ+GitHub Actions の選択を設計で明示する
- Coolify から全デプロイ先へ root 相当 SSH は避けられない。緩和は FW とネットワーク分離で行う
- Grafana Cloud Free は 50GB/月・14 日保持。auditd(execve) を全量送ると超過する → ルールを絞る + journal/Access ログ優先
- Access JWT 検証は Go の `go-oidc/v3` で RemoteKeySet、AUD tag と issuer を検証
- Cloudflare Access ログと Logpush の Free 可否、LAUREL 出力パス、Neo23x0 のインストール先、R2 を restic で使う動作、Docker source の二重 JSON 有無は **実機/実アカウントで要検証**
