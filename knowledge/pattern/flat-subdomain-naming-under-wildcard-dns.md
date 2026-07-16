---
title: wildcard DNS 配下ではサブドメインをフラット 1 レベルに固定する
category: pattern
tags: [cloudflare, dns, ssl, naming, coolify, appily, n-wasabi]
created: 2026-07-16
project: global
sources:
  - https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/
  - Muraki/projects/omatase/.designs/20260716-coolify-deploy.md
---

## Context

`*.appily.run` / `*.n-wasabi.org` のような **wildcard CNAME → Cloudflare Tunnel → Nginx → Coolify Traefik** 構成で、
新規アプリのホスト名を決めるとき。「アプリごとに `api.<app>.<zone>` と入れ子にして構造を表現したい」は自然な発想だが、
このスタックでは**コストが跳ね上がる**。omatase の n-wasabi.org 移行 (2026-07-16) で判断した。

## What

**サブドメインはフラット 1 レベルに固定する。**

| 採用                          | 不採用                        |
| ----------------------------- | ----------------------------- |
| `omatase.n-wasabi.org`        | `omatase.n-wasabi.org` (web)  |
| `omatase-api.n-wasabi.org`    | `api.omatase.n-wasabi.org` ✗  |

役割はドット (`.`) でなく**ハイフン (`-`) で表現する**。

根拠 2 つ (どちらも一次情報):

1. **DNS wildcard は 1 レベルのみマッチする**。`*.n-wasabi.org` は `omatase.n-wasabi.org` にマッチするが
   **`api.omatase.n-wasabi.org` にはマッチしない** → 入れ子にすると**アプリを足すたびに DNS レコード追加**が要る
2. **Cloudflare Universal SSL は full setup zone で apex + 第 1 レベルまで**。公式 docs 明記:
   *"For full setup zones that need coverage beyond first-level subdomains, use Total TLS or advanced certificates"*
   → 第 2 レベルは**証明書が出ない**。Total TLS / advanced certificate は**有料**

つまり入れ子命名は「DNS 作業の恒久化 + 課金」を買う。フラットなら **wildcard 1 本・DNS 作業ゼロ・無料**。

**apex (`<zone>`) を個別アプリに割り当てない**のも同根 + 別理由:
- apex は wildcard の**対象外**なので専用 CNAME (flatten) が別途要る
- apex は zone の顔。1 プロダクトが占有すると後続アプリが構造的に格下になる。LP / ポータルに温存する

## Why

wildcard CNAME の価値は「**新規アプリ追加時に DNS を触らなくてよい**」ことに尽きる
(`library/cloudflare-tunnel-2026.md` の設計判断)。入れ子命名はこの価値を**ちょうど無効化する** —
wildcard を張った意味が消え、しかも SSL の課金まで付いてくる。

得られるのは URL の見た目の階層感だけで、これは `-` 区切りでほぼ同等に表現できる。
交換レートが悪すぎる。

## How to apply

新規アプリのホスト名を決めるとき:

1. **`<app>.<zone>` と `<app>-<role>.<zone>` の 2 パターンだけ**を候補にする。ドットを 2 つ以上増やさない
2. 入れ子にしたくなったら「wildcard が効かなくなる + 証明書が有料になる」を思い出す。
   どうしても必要なら、その 2 つのコストを設計doc に明記して判断を上げる
3. apex は使わない (将来の LP / ポータル用に空けておく)
4. **例外を作るときは wildcard の効かないホストが 1 つ増える**ことを意味する。DNS レコードと証明書の担当を設計に書く

### ドメイン併存 (移行時)

zone を移行するときは **Coolify の `domains` にカンマ区切りで canonical と alias を並べる**
(`"https://<canonical>,https://<alias>"`)。追加コストはカンマ 1 つ。既に配った URL を壊さない。

- **ドメインの正典は Coolify の `domains` 1 箇所**に閉じる。Nginx / Cloudflare 側に redirect を置いて二重化しない
  (「片方だけ直して直らない」調査を将来生む)
- `domains` の PATCH 後は **force redeploy が必要** (Traefik ラベル再生成)
- **CD の smoke は canonical / alias の両方にかける**。片方しか見ない CD は、もう片方が 404 / 302 に落ちても緑のまま通る

新規 zone 側で要る作業は **wildcard CNAME (proxied, SSL/TLS = Full (Strict)) + Nginx vhost 1 本**だけ。
**cloudflared は変更不要** — ingress が catch-all `http://localhost:80` (Nginx) なので新ホストも自動で流れる。

配線確認は**存在しないホスト**を叩く: `https://<random>.<zone>/` が **404** なら
「DNS wildcard → Nginx → Traefik が生きていて、Coolify がそのホストを知らないだけ」= 配線 OK。
接続不能 / 502 なら配線が壊れている。
