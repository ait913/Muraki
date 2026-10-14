---
title: オンプレ Coolify でのアプリビルドがサーバー全体を固める (main push = フルビルド)
category: gotcha
tags: [coolify, appily, oom, swap, nextjs, deploy, webhook]
created: 2026-10-14
project: global
sources:
  - "sessions/2026-10-14-b837d104 (wasawasa の文書だけの push → pnpm build → 全サービス停止)"
---

## Context

appily / n-wasabi.org のアプリは全てオンプレ 1 台 (Celeron G1840 2 コア、RAM 3.7GiB、swap 3.8GiB、コンテナ約 40) の Coolify で動く。Dockerfile build pack のアプリは **main への push ごとに webhook → サーバー上で `docker build`** する (watch_paths 未設定なら文書だけの変更でもフルビルド)。

## What

2026-10-14 14:00、wasawasa の設計 doc だけのコミットを main に push → Coolify が `pnpm build` (Next.js 16) を開始 → 14:05 `pcp-pmie: Severe demand for real memory 960pgsout/s` → 14:08 snapd watchdog kill → 14:47 journald watchdog kill → 14:54 再起動まで約 50 分、Cloudflare Tunnel (cloudflared) ごと全ドメインが 530。同日それ以前の 3 回のビルドは通っており、bloom の動画配信負荷と重なった回で閾値を越えた。アプリの `limits_memory` は 0 (無制限) でビルドは止まらない。

## Why

ビルドはランタイムと同じホストのメモリを奪い合う。swap 地獄になると cloudflared / journald も応答不能になり、OOM killer が発動せずに「固まる」形で落ちる (kill されないので自然復帰しない)。

## How to apply

- **main への push = 本番ホストでのビルド**と考える。文書だけのコミットを main に直接 push しない (設計 doc は機能ブランチのマージにまとめる)。
- Coolify アプリには watch_paths を設定し、イメージに影響しないパス (`.designs/` `docs/` `*.md` `tests/`) の変更ではデプロイしない。
- **ビルドは原則自サーバーで続ける (Touri 裁定 2026-10-14: 足りなければビルドが止まれば良い)。wasawasa のみ GitHub Actions ビルドへ移す案は保留中** (ビルド時の空きメモリ減が 0.9〜1.9GB で他アプリより突出。bloom-web 0.2〜1.2GB、atender-api 0.7〜1.5GB、Go 製 0.03〜0.7GB、PCP 20 秒サンプル)。サーバー増強後に再調整。自サーバー側の守り (2026-10-14 適用済み):
  - **earlyoom** (`/etc/default/earlyoom`: `-m 5 -s 100 -r 60 --avoid '^(cloudflared|sshd|dockerd|containerd|containerd-shim-runc-v2|mysqld|nginx|systemd|systemd-journald|postgres|traefik|earlyoom)$'`)。空きメモリ 5% (当初 8%、2026-10-14 に緩和) で**最大のプロセス** (= 暴走したビルドやアプリ) に SIGTERM、swap は見ない (既定の swap 10% 条件だと 3.8GB の swap を使い切るまで発動せず先に固まる)。ログは `journalctl -u earlyoom`。★ **ビルドではなく稼働中アプリを殺す**: 2026-10-14 の wasawasa ビルド中、earlyoom が kill したのは本番の next-server (2 回) と fwupd で、ビルドは生き残った。`docker build` の子プロセスは dockerd の `oom_score_adj=-500` を継承して oom_score が約 338 になり、アプリ (約 666) より「殺しにくい」側に回るため。→ 2026-10-14 18:5x に dockerd の adj を 0 へ (稼働中 PID へ `echo 0 > /proc/<pid>/oom_score_adj` + drop-in `/etc/systemd/system/docker.service.d/oom-score.conf` `OOMScoreAdjust=0` + `daemon-reload`、Docker 再起動なし)。直後の wasawasa ビルドで earlyoom は `next-build` (RSS 1881MiB、badness 847) だけを kill し、デプロイは failed、本番は旧イメージのまま 200。狙いどおりビルドだけ止まることを実測で確認
  - systemd-oomd は一度入れて撤去した: 選定基準が「回収されている (pgscan) cgroup」なので、暴走したビルドではなく巻き込まれた側のアプリを殺しうる。「最大プロセスを 1 つ殺す」earlyoom の方が狙い (ビルドだけ止める) に合う (Touri 裁定 2026-10-14)
  - Coolify `concurrent_builds` = 1 (`PATCH /servers/<uuid>`)
  - 全アプリ 25 本に `limits_memory=512m` / `limits_memory_swap=1024m` (Coolify) + 稼働中コンテナに `docker update --memory 512m --memory-swap 1g` (再起動なしで即時)。**Coolify の limits はランタイムだけで `docker build` には効かない**。新規アプリ作成時も同値を入れる
- **cgroup v2 のメモリ段 (2026-10-14 適用、Docker 再起動なし)**: Coolify はアプリ/ビルドに cgroup を指定できない (`custom_docker_run_options` の `--cgroup-parent` / `--memory` は黙って捨てられる、daemon.json `cgroup-parent` は再起動要) ので、ホスト側で付ける。
  - systemd: `systemctl set-property` で system.slice `MemoryMin=256M MemoryLow=2400M` (memory_recursiveprot なので**親に付けないと子の保護が効かない**)、cloudflared 64M / ssh 128M / journald 64M に MemoryMin、docker / containerd 256M・mysql 64M に MemoryLow (`/etc/systemd/system.control/`)
  - ウォッチャー `mem-tiers.service` (`/usr/local/sbin/mem-tiers`、1 秒ポーリング): コンテナ scope に `set-property --runtime MemoryLow` (Coolify 本体 40〜256M、label `coolify.environmentName=production` は 32M、dev はなし)。ビルドは各 RUN ステップが **`/sys/fs/cgroup/system.slice/system.slice:docker:<id>`** という systemd ユニットでない cgroup になる (moby が systemd 形式の親文字列を cgroupfs パスとして使う) ので、`memory.max=1843M` (当初 1536M、同日 1.8G へ緩和) / `memory.swap.max=1024M` / `memory.oom.group=1` を直接書く
  - 実測 (wasawasa、上限 1.5G+swap 1G): Turbopack のコンパイル (2.4 分) は上限内で完走、続く `Running TypeScript` で exit 137 (cgroup 内 OOM)。earlyoom は発動せず、本番は終始 200。→ ビルドだけが自分の枠の中で死ぬ形になった
  - 戻し方: `systemctl disable --now mem-tiers`、`/etc/systemd/system.control/` の該当 drop-in 削除 + `daemon-reload`
- 落ちた時の切り分け: 全ドメイン 530 = cloudflared 不通。`ssh aisaba` 復帰後 `last -x`、`journalctl -b -1 -p warning | grep -iE "watchdog|memory"` で前回起動の末尾を見る。再起動直後は数分 404/502 が出るが Coolify の起動待ち (焦って Docker daemon を再起動しない)。
