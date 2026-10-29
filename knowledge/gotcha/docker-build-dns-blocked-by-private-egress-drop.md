---
title: iptables:false + ufw で「コンテナ → private 宛 DROP」を入れると Coolify のビルドだけ DNS が死ぬ (default bridge の resolv.conf が LAN ルータ)
category: gotcha
project: global
tags: [docker, ufw, dns, coolify, buildkit, iptables-false, egress]
created: 2026-10-29
sources:
  - aiserver2 での実走 (sessions/2026-10-29-b45758d0.md 78)
  - projects/aiserver/ops/ufw/before.rules.aiserver-block
---

## Context

aiserver2 は Docker `iptables: false` + ufw 主管。Phase 3-1 で `-s 10.0.0.0/8 -o enp2s0 -d 192.168.0.0/16 -j DROP` (コンテナから LAN への egress 遮断) を入れた。稼働中のアプリは全部動いていたのに、翌朝 ais-pass の Coolify デプロイが `pnpm install` で `getaddrinfo EAI_AGAIN registry.npmjs.org` で落ちた。

## What

- Coolify の user network (`10.0.x.0/24`) に居るコンテナは Docker の **embedded DNS (127.0.0.11)** を使い、名前解決はホスト側で行われる → LAN 遮断の影響を受けない
- **default bridge (`docker0`、ここでは 10.0.0.0/24) のコンテナは embedded DNS を使わず、ホストの `/etc/resolv.conf` を写した nameserver を直接叩く**。systemd-resolved の `127.0.0.53` はコンテナから届かないので Docker が upstream (`192.168.3.1` = LAN ルータ) に書き換える → その宛先が EGRESS-PRIV の DROP に当たる
- Coolify のビルド (buildkit の `RUN` ステップ) は default bridge で走る。前夜の大量デプロイが通ったのは build cache が効いていただけで、cache が外れた `RUN corepack enable && pnpm install` で初めて露見した
- 対処: DROP の前に `-d 192.168.3.1 -p udp --dport 53 -j ACCEPT` (tcp も) を置く。LAN への他の到達は遮断のまま (`nc -z 192.168.3.1 80` は失敗することを確認)

## Why

Docker の DNS 経路が network の種類で違う (user-defined = embedded DNS、default bridge = resolv.conf 直叩き)。ufw で egress を絞るとき「アプリは動く」だけ見ると、ビルド時にしか使われない default bridge の経路を見落とす。

## How to apply

- コンテナ → private 宛を DROP するときは、**default bridge の resolv.conf (`docker run --rm --network bridge alpine cat /etc/resolv.conf`) の nameserver** への 53 だけ先に ACCEPT する
- 検証は「稼働アプリの疎通」ではなく `docker run --rm --network bridge alpine nslookup <名前>` と、cache を使わないビルド 1 回
- 恒久策の候補: `daemon.json` に `"dns": ["1.1.1.1"]` (daemon 再起動が要るので aiserver2 では不可 → ufw 側で対処)
