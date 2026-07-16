---
title: Coolify の healthcheck が localhost→::1 で落ちる (Node の HOSTNAME=0.0.0.0 は IPv4 のみ bind)
category: gotcha
tags: [coolify, healthcheck, docker, ipv6, nextjs, standalone, node, alpine, busybox, go]
project: global
created: 2026-07-16
sources:
  - 実測: omatase feature/coolify-deploy の Reviewer フェーズで Docker 実走 (2026-07-16)
  - Muraki/projects/omatase/.designs/20260716-coolify-deploy.md
---

## Context

Coolify に app を建てるとき `health_check_host: "localhost"` を設定すると、
Coolify はコンテナ内で以下の compose healthcheck を実行する:

```
["CMD-SHELL", "curl -s -X 'GET' -f 'http://localhost:<port>/healthz' > /dev/null || wget -q -O- 'http://localhost:<port>/healthz' > /dev/null || exit 1"]
```

alpine ベースの Next.js standalone コンテナ (`ENV HOSTNAME=0.0.0.0`) でこれが**常に失敗**する。
Go の backend では同じ設定で成功するため、原因の切り分けが難しい。

## What

Node (Next standalone) に `HOSTNAME=0.0.0.0` を渡すと **IPv4 のみ** bind する:

```
tcp  0.0.0.0:3000  LISTEN      # tcp6 の listener が無い
```

一方 Docker の `/etc/hosts` は localhost を **両方**に解決させる:

```
127.0.0.1  localhost
::1        localhost ip6-localhost ip6-loopback
```

busybox の wget は `localhost` を **::1 優先**で引き、fallback しない → `Connection refused` → healthcheck 失敗 → retries 尽きて unhealthy → **デプロイ失敗**。

実測 (omatase web イメージ、コンテナ内から):

| target | 結果 |
| --- | --- |
| `wget http://127.0.0.1:3000/healthz` | exit 0 |
| `wget http://localhost:3000/healthz` | **exit 1 (Connection refused)** |
| `wget http://[::1]:3000/healthz` | exit 1 |

Go backend は `:8080` で listen すると **dual-stack** (`:::8080`) になるため localhost / ::1 とも通り、**同じ設定でも落ちない**。この非対称が誤帰属を生む。

## Why

- Go の `net.Listen("tcp", ":8080")` は wildcard = IPv6 wildcard (v4-mapped 受け) → dual-stack
- Node の `server.listen(port, "0.0.0.0")` は IPv4 wildcard を**明示指定**したことになり IPv6 listener を作らない
- `HOSTNAME=0.0.0.0` は「コンテナ外 (Traefik) から届かせる」ためには**正しい**。Traefik はコンテナ IP (172.17.0.x) を叩くので 0.0.0.0 bind で到達できる。**問題は in-container healthcheck の localhost 経路だけ**に出る

### ★ CI のポート公開プローブでは捕まらない

`docker run -p 18080:3000` + ホストから `curl 127.0.0.1:18080/healthz` は **0.0.0.0 bind で普通に 200 を返す**。
`command -v wget` の存在アサートも通る。つまり **CI は緑のまま、初回デプロイだけが落ちる**。
Coolify の healthcheck を検証したいなら **`docker exec` でコンテナ内から実 CMD-SHELL を実行**する必要がある。

## How to apply

**設計時**: Coolify + Node/Next の組合せでは **A を採る** (両案とも実測で healthcheck exit 0 だが、依存する前提が違う):

- **★ A (推奨): `ENV HOSTNAME=::`** — Node が dual-stack (`:::3000`) で bind。localhost/127.0.0.1/::1 全て通る。外部到達性も維持 (実測 200)
- **B (非推奨): `health_check_host: "127.0.0.1"`** — Coolify 側 config で localhost を避ける。Dockerfile を触らない

**A を選ぶ理由 (omatase 2026-07-16 の裁定)**:

1. **B は「Coolify が `health_check_host` をそのまま healthcheck URL に埋める」という前提に依存する**。これは実装読みベースの推測で、**実機の生成 compose では未確認**。正規化されたり別経路で埋められたら B は黙って効かない
2. **A はその前提から独立する**。コンテナが dual-stack なら Coolify が localhost / 127.0.0.1 / ::1 の**どれを使っても成立する**。Coolify 側の挙動を知らずに済む
3. **A は Go (`:::8080`) との bind 非対称を消す**。この非対称こそが「web だけ落ちる」を生み、原因の誤帰属 (イメージや wget を疑う) を招く。2 app の bind を揃えること自体に価値がある

一般化: **「相手側の設定で回避する」案と「自分側を仕様に対して頑健にする」案が並んだら、後者を採る**。前者は相手の未検証な挙動に賭ける取引になる。

**検証時**: healthcheck の検証は**必ずコンテナ内から**実行する。ホスト側のポート公開プローブは healthcheck の代理にならない:

```sh
docker exec <c> sh -c "curl -s -X 'GET' -f 'http://localhost:<port>/healthz' > /dev/null || wget -q -O- 'http://localhost:<port>/healthz' > /dev/null || exit 1"; echo $?
```

**切り分け**: 「Go は通るのに Node だけ unhealthy」を見たら bind の stack を疑う (`netstat -ltn` で `0.0.0.0:` か `:::` か)。イメージや wget の有無ではない。
