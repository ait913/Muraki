---
title: "Coolify の Docker Compose は全 service に env_file .env を注入する (秘密分離は raw モード必須)"
category: gotcha
project: ais-pass
tags: [coolify, docker-compose, secrets, raw-compose, traefik, build-context]
created: 2026-10-27
sources:
  - Coolify v4.5.0 `app/Jobs/ApplicationDeploymentJob.php` (「Always add .env file to services」)
  - sessions/2026-10-26-e77c0042 (AIS Pass Go 版の受入 A で実測)
---

## Context

AIS Pass Go 版は「1 プロセスが全秘密を読めない」ことを設計目標にし、compose の service ごとに `environment` を分け、各 binary が自分の env キー集合以外の `PASS_` / `PAD_` / `SIGNER_` env を見つけたら exit 1 する (厳格 env 検証)。Coolify の Docker Compose リソースでリソース env に 14 秘密を入れてデプロイしたら signer / migrate が `unexpected env: PASS_PG_SUPERUSER_PASSWORD` で exit 1 した。

## What

1. **parse モード (既定) は無条件で全 service に `env_file: ['.env']` を足す**。`.env` にはリソース env の全キー (+ `COOLIFY_*` / `SERVICE_NAME_*`) が入るので、**全コンテナが全秘密を読める**。service 単位の `environment` で分けても無意味。Phase 0 で「service 単位の environment が成立」と見えたのは compose にインラインで書いた env だけを見ていたため。
2. **raw compose モード** (`application_settings.is_raw_compose_deployment_enabled = true`、API: `PATCH /applications/{uuid}` に `{"is_raw_compose_deployment_enabled":true}` で入る) は compose をそのまま使い、`.env` は `docker compose --env-file` の**補間にだけ**使う (コンテナには入らない)。ただし Coolify は `<uuid>` network の付与も Traefik label の生成も `docker_compose_domains` も行わない → 経路は自分で書く: proxy が居る共有 network `coolify` (external) に公開 service だけ入れ、`traefik.enable=true` / `traefik.docker.network=coolify` / `traefik.http.routers.<name>.rule=Host(...)` / `.entrypoints=http` / `traefik.http.services.<name>.loadbalancer.server.port=<port>`。
3. raw モードのパーサは **`labels` を map 形式で書くと壊す** (`non-string key in services.pass.labels: 0`)。リスト形式 (`- key=value`) で書く。
4. compose の **`build.context` は repo root 基準** (`context: .`、`dockerfile: deploy/Dockerfile`)。Coolify は compose を clone root に書き出して実行するので、`deploy/compose.yaml` から見た `..` は `/artifacts` を指して `lstat /artifacts/deploy: no such file` で build が落ちる (parse / raw 共通)。
5. `profiles:` 付き service は build されない。必要なら `docker_compose_custom_build_command` に `docker compose --profile <p> build` (Coolify が `-f` / `--env-file` を注入する)。
6. 命名: parse モードはコンテナ `<service>-<uuid>-<timestamp>`、raw モードは compose 既定の `<uuid>-<service>-1`。network / volume はどちらも `<uuid>_<name>`。parse モードで一度デプロイすると external network `<uuid>` に `coolify-proxy` が繋がったまま残る (`docker network disconnect <uuid> coolify-proxy; docker network rm <uuid>`)。
7. `PATCH /applications/{uuid}/envs/bulk` は各キーを production + preview の 2 行作る。`is_preview==true` の行を DELETE で掃除。

## Why

`ApplicationDeploymentJob::deploy_docker_compose_buildpack` の非 raw 分岐に `$service['env_file'] = ['.env']` が固定で入っている (設定で外せない)。raw 分岐は `docker_compose_raw` を無加工で `docker-compose.yaml` に書き出す。

## How to apply

- 秘密を service ごとに分けたい compose は **raw モードを最初から前提**にし、Traefik label と `coolify` network を compose に書く。受入で「他 service の秘密が env に無い」を `docker inspect` のキー名で必ず測る。
- 公開ホストを本番と衝突させずに検証したい時は label の Host を `${ROUTE_HOST:-prod.example}` で補間し、検証中だけリソース env に `ROUTE_HOST=<probe>` を置く (raw モードなら補間専用でコンテナには入らない)。
