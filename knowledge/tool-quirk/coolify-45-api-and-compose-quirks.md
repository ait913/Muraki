---
title: Coolify 4.5.0 の API と compose 解釈の癖 (raw フラグは PATCH 不可 / dockercompose 作成 route 無し / build.context は repo ルート基準 / env の自動生成 / destination の付け替え不可)
category: tool-quirk
project: global
tags: [coolify, api, docker-compose, destination, traefik, build-context, env]
created: 2026-10-29
sources:
  - aiserver2 での実走 (sessions/2026-10-29-b45758d0.md 42〜52)
  - https://raw.githubusercontent.com/coollabsio/coolify/v4.5.0/openapi.yaml
  - projects/aiserver/.knowledge/research-coolify-isolation-20261029.md
---

## Context

2026-10-29 に Coolify 4.5.0 (単一 localhost サーバー) で、API だけでリソース作成・destination 分離・raw compose を回した時に踏んだ癖。UI を使わずに Leader が自律で回す前提の記録。

## What

- **`POST /applications/dockercompose` (inline compose の作成) は 4.5.0 の OpenAPI に無い** → `{"message":"Not found."}`。raw compose を API で建てるには **git repo に compose を置いて `POST /applications/private-github-app`** (`build_pack: dockercompose`, `docker_compose_location`) を使う。小さな静的サイトでも repo が 1 本要る (hyte-art は `ait913/hyte-art` を作った)
- **`is_raw_compose_deployment_enabled` / `is_force_https_enabled` / `is_auto_deploy_enabled` は PATCH しても反映されない** (GET は null のまま)。非 raw でも Coolify の変換は `user` / `read_only` / `cap_drop` / `security_opt` / `tmpfs` / `pids_limit` / `mem_limit` / `healthcheck` / `labels` / 固定 IP の `networks` を保持し、自分の network `<uuid>` と `coolify.*` labels を足す。実害は無かった
- **相対 bind `./x` は `/data/coolify/applications/<uuid>/x` に解決される** (repo の中身はそこに無い)。先に deploy すると docker が **その path をディレクトリとして作る** → 後からファイルを置いても mount に失敗する。`rm -rf` してからファイルを置く
- **`build.context` は compose ファイルの位置ではなく repo ルート (base_directory) 基準**。`context: ../..` は `lstat /deploy: no such file` で死ぬ。正解は `context: .` + `dockerfile: deploy/Dockerfile` (ais-pass と同形)。手元の `docker compose config` は compose-spec 解釈なので当てにならない
- **compose の `${VAR:-default}` を見つけると Coolify がリソース env に `VAR` (値 null) を自動生成する** (preview 側も)。`POST /envs` は「既存」で弾かれるので **`PATCH /applications/{uuid}/envs`** で値を入れる
- **destination (`POST /servers/{uuid}/destinations`) は API で作れる** (10.0.x.0/24、IPv6 無し、proxy が自動 attach)。既存リソースの destination 付け替えは不可 (clone + データ移植)
- **`GET /servers/{uuid}` の `proxy.last_saved_proxy_configuration` は UI の Save で disk に上書きされる**。disk を手で変えたら DB 側も揃える: `docker cp` で compose を coolify-db に入れ、`psql -f` で `UPDATE servers SET proxy = (proxy::jsonb || jsonb_build_object('last_saved_proxy_configuration', :'cfg'))::json`。`psql -c` では psql 変数が展開されない
- Traefik の `--entrypoints.<ep>.http.middlewares=...@file` で entrypoint 全体に ipAllowList を掛けると、**Traefik 自身の healthcheck (`wget localhost/ping`) が IPv6 loopback から来て 403 → unhealthy** になる。sourceRange に `::1/128` を足す
- **Coolify 自前の `dynamic/coolify.yaml` は http entrypoint の coolify.aisaba.net router に `redirect-to-https` を付ける**。TLS 終端が Cloudflare で Traefik に http で届く構成だと 302 ループになる (UI も API も)。aiserver2 では host nginx が Traefik を通さず `127.0.0.1:8000` に直結していたので見えていなかった。対処は file provider に **priority の高い router (`aiserver-coolify-ui` → `http://coolify:8080`)** を置いて上書き (Coolify が coolify.yaml を再生成しても消えない)
- **`POST /applications/{uuid}/clone` の癖** (2026-10-29、15 グループで実走): (1) clone 先は `is_auto_deploy_enabled` が **true** になる (元が false でも) → 直後に PATCH で戻す。(2) `custom_labels` (Traefik の router / service label) が**旧 uuid 名のまま**コピーされる → deploy 時に Coolify が新 uuid で再生成するが、**`loadbalancer.server.port` は元の値を引き継ぐ**。ports_exposes を 80→8080 に変えても label が 80 のままで 502 になるので、`custom_labels` を base64 デコードして port を書き換えて PATCH する。(3) `custom_network_aliases`、env (preview 含む)、storages (persistent_storages) は写る。volume の中身は `clone_volumes:false` なら空 → `docker run --rm -v old:/from:ro -v new:/to alpine cp -a` で移す。(4) 旧 app が同じ fqdn を持っていると `PATCH domains` が **409** → `force_domain_override:true` を body に足す
- **`POST /databases/{uuid}/clone` は OpenAPI にあるが PG の移動には使わなかった**: `POST /databases/postgresql` で旧と同じ user / password / db / image で作り、`pg_dumpall --globals-only` + DB ごとの `pg_dump -Fc` → `pg_restore` → 全 user table の count 照合、で移す (`GET /databases/{uuid}` に `postgres_password` が平文で返る)
- Traefik docker provider は **health が `starting` のコンテナを router に載せない** → 新規デプロイ直後の smoke は healthy を待つ

## Why

UI 前提の機能 (raw フラグ、inline compose) が API に露出していない。compose の解釈も docker compose とは別実装なので、手元検証と実機の結果がずれる。

## How to apply

- API だけで建てるなら「repo + private-github-app」に統一し、raw フラグは諦めて変換結果 (`GET` の `docker_compose`) を読んで確認する
- compose の build は `context: .` 固定。bind は絶対パスか、`/data/coolify/applications/<uuid>/` に先にファイルを置く
- `${VAR:-x}` を使ったら deploy 前に envs を GET して PATCH
- proxy を触る時は DB と disk の整合を先に (UI から Restart できる状態を保つ)
