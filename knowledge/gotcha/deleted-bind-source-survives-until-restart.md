---
title: ホスト側の bind mount 元を消しても稼働中コンテナは動き続け、再起動で初めて起動不能になる (後片付け前に全コンテナの Mounts を grep する)
category: gotcha
project: global
tags: [docker, bind-mount, cleanup, reboot, coolify, nginx]
created: 2026-10-29
sources:
  - aiserver2 での実走 (sessions/2026-10-29-b45758d0.md 71 / 86)
---

## Context

aiserver2 で host nginx を廃止した後、「host nginx の設定ディレクトリ」と見なして `/etc/aisaba-platform/nginx/` を削除した。直後の外形確認 (apps.aisaba.net 200) は通っていた。数時間後にサーバーを shutdown → 起動すると、そのディレクトリ内の 1 ファイルを bind mount していたコンテナ (nexom-web) だけが `failed to fulfil mount request: open /etc/aisaba-platform/nginx/edge-auth.conf: no such file or directory` (exit 127) で起動できず、配信ホスト 7 本が Traefik の 404 になった。

## What

- bind mount はコンテナ起動時に解決される。起点ファイルをホスト側で `rm` しても、既に mount 済みのコンテナは inode を掴んでいるので読み続ける
- したがって「消した後に外形 200」は何の証明にもならない。露見するのは次の `docker start` / `docker compose up` / ホスト再起動
- Coolify の app は `restart: unless-stopped` なので、再起動で落ちたコンテナは `docker ps -a` に `Exited (127)` で残る。`.State.Error` に mount の失敗理由が入る
- 復旧はファイルを元の owner / mode で戻して `docker start <container>` するだけ (restic のように owner / mode を保つバックアップが要る。`restic restore <snap> --include <path> --target /`)

## Why

削除時の判断材料が「何のためのディレクトリか」という由来の記憶で、「今だれが参照しているか」の実測ではなかった。host 側のサービスを container に置き換える移行では、旧 host 用のファイルを container 側が引き続き bind している (edge 認証の map など) ことが普通にある。

## How to apply

ホストのファイル / ディレクトリを消す前に、全コンテナ (停止中も含む) の bind 元を列挙して照合する:

```
sudo docker inspect --format '{{.Name}}{{range .Mounts}}{{if eq .Type "bind"}} {{.Source}}{{end}}{{end}}' $(sudo docker ps -aq) | grep -F '<消す path>'
```

1 件でもヒットしたら消さない。compose の `volumes:` にも同じ path が書かれているはずなので、設計側 (compose) を直してからにする。後片付けの受入条件は「外形 200」でなく「`docker restart` 後も 200」にする。
