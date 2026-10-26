---
title: aiserver2 は Docker `iptables: false` + ufw 主管。ブリッジ間隔離は ufw の 1 行が担う
category: gotcha
project: global
tags: [docker, ufw, iptables, bridge, network-isolation, internal-network, coolify, aiserver2]
created: 2026-10-26
sources:
  - /etc/docker/daemon.json (iptables=false, ip=127.0.0.1, default-address-pools 10.0.0.0/8 /24)
  - /etc/ufw/before.rules 46 行目 (2026-10-26 に置換、バックアップ before.rules.bak-20261026-bridge-isolation)
  - projects/ais-pass/.knowledge/coolify-compose-isolation-20261026.md (Phase 0 の実測)
---

## Context

AIS Pass Go 書き直しの Phase 0 で、`internal: true` の compose network に `coolify` network や既定 `bridge` のコンテナから TCP が通ることを実測した (2026-10-26)。原因はホスト設定。

## What

- `daemon.json` は **`"iptables": false`** (Docker に iptables を触らせず ufw が全部管理する、意図的な設計)。`"ip": "127.0.0.1"` で publish 既定は localhost bind、egress の MASQUERADE は `before.rules` の `*nat` に手書き
- この設計では Docker のブリッジ間隔離 (`DOCKER-ISOLATION-*`)・`internal: true`・公開ポートの DNAT が**全部無効**。隔離は ufw の FORWARD ルールだけが担う
- 2026-10-26 以前の `before.rules` 46 行目は `-A ufw-before-forward -s 10.0.0.0/8 -j ACCEPT` で**宛先無制限** → 別ブリッジ宛も転送されていた。**置換後: `-A ufw-before-forward -s 10.0.0.0/8 -o enp2s0 -j ACCEPT`** (外向き NIC 宛のみ)。ブリッジ間は `DEFAULT_FORWARD_POLICY="DROP"` に落ちる
- 置換後の実測: `bridge` → `coolify` の proxy `10.0.1.9:80` は timeout、コンテナ → `github.com:443` は open、同一 network 内は open、36 コンテナ無停止、公開 URL 正常
- 同一 network (`coolify`、36 コンテナ全部) 内は引き続き互いに届く。これは Coolify の既定で、分けるなら app ごとの network (別タスク)
- `br_netfilter` は未ロードなので同一ブリッジ内の通信は iptables を通らない。ufw の FORWARD ルールはブリッジ間だけに効く

## Why

ufw と Docker を両方 iptables の管理者にすると衝突する (Docker の DOCKER チェーンが ufw の INPUT を素通りする有名な問題)。Touri はそれを避けて ufw 一本にした。正しい選択だが、その場合 Docker が本来入れる隔離ルールを ufw 側で肩代わりする必要があり、1 行の宛先指定が抜けていた。

## How to apply

- **`iptables: true` に戻さない** (A 案は却下: daemon 再起動が要り、Coolify 本体の `0.0.0.0:8000` / `6001-6002` が ufw を素通りして LAN に露出する副作用がある)
- Docker network を跨ぐ通信が必要になったら、`before.rules` に明示の `-i br-xxx -o br-yyy` ルールを足す (既定は DROP)
- 新しい compose で `internal: true` を書いても Docker は強制しない。10.0.0.0/8 以外のサブネット (例: 172.30.x) を使えば 46 行目に当たらず外に出られないので実質 internal になる。10.0.0.0/8 の Coolify 自動 network は外に出られる
- 戻し方: `sudo cp /etc/ufw/before.rules.bak-20261026-bridge-isolation /etc/ufw/before.rules; sudo ufw reload`
- 残課題 (別タスク「サーバー堅牢化の棚卸し」): 同一 network 36 コンテナの相互到達、Coolify の 0.0.0.0 publish、認証無しの内部サービスの有無、DB パスワード強度
