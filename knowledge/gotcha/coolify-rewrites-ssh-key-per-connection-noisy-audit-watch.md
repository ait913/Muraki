---
title: Coolify は自サーバーへ接続するたびに SSH 鍵ファイルを書き直す — 鍵ディレクトリの auditd 監視は自己書き込みを除外しないとアラートがノイズになる
category: gotcha
project: aiserver
tags: [coolify, auditd, laurel, grafana-alerting, logql, noise]
created: 2026-10-30
sources:
  - Muraki/sessions/2026-10-29-b45758d0.md (100)
  - aiserver .designs/20261029-aiserver2-hardening.md A15
---

## Context

aiserver2 の堅牢化で `/data/coolify/ssh/` (コンテナ内 `storage/app/ssh/`) を auditd で監視 (`-k coolify_keys`) し、Grafana の A15b (info) で Slack に流していた。ルールが正しく効き始めた途端、system-events に 1 時間 4〜21 件、デプロイや再起動の前後は 90 件の通知が並んだ。

## What

生の audit.log 704 件の内訳:

- 673 件 `comm=php`: Coolify が **ssh するたびに** `keys/ssh_key@<server uuid>` を DB の秘密鍵から書き直す (+ `.lock`)。さらに `keys/.test_write_<hex>` を作って消す書き込み可否プローブ
- 19 件 `comm=ssh`: `mux/mux_<uuid>` の ControlMaster ソケット作成
- 12 件 `comm=chown` (busybox): Coolify コンテナ起動時の所有者合わせ

Coolify は数分ごとのサーバー状態チェック、デプロイ、ターミナル接続のたびに ssh するので、鍵ファイルの書き直しは「平常運転」。

## Why

鍵ファイルを「置いておく」のでなく「使う直前に DB から書き出す」設計なので、ファイル監視は Coolify 自身の動作と第三者の改変を区別できない。auditd の `-w` は directory に付けると再帰 (`-F dir=`) になり、`mux/` のソケットも拾う。

## How to apply

- 監査ログには残し、**通知だけ LogQL の行フィルタで除外**する。LAUREL の JSON は `comm` が `key` より前に並ぶので
  `{job="audit",key=~"...|coolify_keys|..."} !~ \`"comm":"(php|ssh|chown)"[^}]*"key":"coolify_keys"\``
  (`ops/grafana/provision-alerts.sh` の A15b。php 以外、例えば root の shell が鍵を触ったら鳴る)
- auditd 側で `-F exe!=` を付けて消す案は採らない。監査証跡が消えるのと、コンテナ内 php の path は他のコンテナにも同名で存在する
- 新しい監査 watch を足したら、1 時間後に `grep -h 'key="<k>"' /var/log/audit/audit.log* | grep -o 'comm="[^"]*"' | sort | uniq -c` で誰が触っているか見てからアラートに繋ぐ
- 似た話: `aiserver-docker-logmap` が 60 秒ごとに全コンテナのログへ無条件 `setfacl` → `acl_exec` の execve 監視が 1 日 6 万件、audit.log が 5 時間でローテート。ACL が既に付いていれば呼ばないように変えた (同日)
