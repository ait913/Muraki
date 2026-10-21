---
title: aisaba ホスト (Ubuntu 22.04) の実態 2026-10 — 毎晩 01:00 再起動 / ufw が Docker も支配 / 24.04 へは docker-ce 先行が必須
category: library
project: muraki
tags: [ubuntu, jammy, docker, ufw, coolify, sshd, release-upgrade, server]
created: 2026-10-22
sources:
  - Muraki/sessions/2026-10-22-acd89e01.md
  - https://docs.docker.com/engine/install/ubuntu/
  - https://raw.githubusercontent.com/coollabsio/coolify/main/scripts/install.sh
  - https://api.launchpad.net/devel/ubuntu/+archive/primary
---

## Context

Coolify (coolify.aisaba.net) と aisaba_platform (nexom@*) が同居する自宅サーバー `aiserver2` (192.168.3.17、i3-4170 / 16G、ベアメタル)。2026-10-22 の棚卸しで分かった「設定から読めない運用上の事実」を残す。

## What

- **毎日 01:00 に自動再起動する** (`ais-auto_reboot.timer` → `/ais/service/reboot.sh` = `shutdown -r now`)。「Docker daemon を再起動すると Coolify の network が飛ぶ」事故 ([[feedback_no_docker_daemon_restart]]) は `systemctl restart docker` 単体の話で、**OS 再起動は毎晩通っている**。needrestart が要求するサービス再起動も翌 01:00 で解消する
- **`/etc/docker/daemon.json` が `iptables: false`** なので、Docker の published port (Coolify 8000 / soketi 6001・6002) も **ufw の default deny に従う**。Docker 公式の「published port は ufw を迂回する」は**この機体には当てはまらない**。LAN から開いているのは 80 と 51000 だけ (nc で実測)。`default-address-pools` は 10.0.0.0/8 size 24 で、ufw の `10.0.0.0/16 ALLOW` は 10.0.255.x までしか覆わない (network が 256 本を超えたら要見直し)
- sshd は 51000 / 鍵のみ / root 不可 / PAM 無効 / MaxAuthTries 3。Tunnel 経由 (`ssh aisaba`) と LAN の 2 経路
- **ルータが 443 をこのホストに転送している** (グローバル IP からの `UFW BLOCK … DPT=443` が毎日数件)。Tunnel 化後は不要なので、ルータ側で転送を消すのが筋 (ホストからは触れない)
- Docker は Ubuntu の `docker.io` 29.1.3 (jammy-updates 由来。ESM ではない)。**24.04 (noble) の `docker.io` は 20.10.25** なので、`do-release-upgrade` の前に Docker 公式 repo の `docker-ce` に移しておかないと**ダウングレード**になる。Coolify の install.sh は `DOCKER_VERSION=latest` / 最低 24 なので docker-ce 29.x で問題ない
- `do-release-upgrade` はサードパーティ repo (docker / nginx.org / nodesource / cloudflared) を**無効化**する。終了後に再有効化が要る。aisaba_platform の venv (python3.10) は 24.04 の python3.12 で全部作り直し
- Ubuntu 22.04 の standard support は **2027-06-01** まで。GA kernel 5.15.0-198 が最新 (2026-10)
- cgroup v2 / `iptables-nft` / overlay2 (実機 `docker info`)

## Why

設定ファイルだけ読むと「daemon 再起動は危険」「Docker は ufw を迂回する」「24.04 に上げれば Docker も新しくなる」と誤推論しやすい。どれも実測で逆だった。

## How to apply

- サーバー更新で再起動が要るなら、**翌 01:00 の自動再起動に乗せる**か、Touri の了承の上で `sudo reboot` する。`systemctl restart docker` だけは避ける
- ポートを開けたい時は ufw の rule が正。Docker 側で `-p` を足しても外からは届かない
- 24.04 へ上げる順序: (1) docker-ce 移行 → (2) venv 再構築の計画 → (3) `do-release-upgrade` → (4) repo 再有効化 + needrestart の docker 除外確認
