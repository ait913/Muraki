---
title: Coolify v4.4.6 のビルド隔離 — custom_docker_run_options の許可リストと BuildKit RUN の cgroup 位置
category: library
tags: [coolify, cgroup-v2, buildkit, docker, systemd, memory]
created: 2026-10-14
project: global
sources:
  - "https://github.com/coollabsio/coolify (v4.4.6) bootstrap/helpers/docker.php convertDockerRunToCompose"
  - "https://github.com/moby/moby daemon/command/daemon_unix.go newCgroupParent"
  - "https://github.com/moby/buildkit frontend/dockerui/config.go, executor/oci/spec.go"
  - "https://github.com/moby/buildkit/pull/6569"
  - "https://docs.docker.com/reference/cli/dockerd/"
---

## Context

オンプレ 1 台 (2 コア 3.7GB) の Coolify で Next.js ビルドがホストを固める件の cgroup v2 階層化調査 (sessions/2026-10-14-b837d104)。

## What

- **`custom_docker_run_options` の許可リスト (v4.4.6 `convertDockerRunToCompose`)**: `--cap-add --cap-drop --security-opt --sysctl --ulimit --device --init --privileged --ip --ip6 --shm-size --dns --gpus --hostname --entrypoint` のみ compose に写像。**`--cgroup-parent` / `--memory` / `--cpus` 等は黙って捨てられる** (エラーなし)。メモリは `limits_*` フィールド経由 (`mem_limit` / `memswap_limit` / `mem_reservation`)。
- Coolify のビルドは coolify-helper コンテナ内から `/var/run/docker.sock` 経由で `DOCKER_BUILDKIT=1 docker build --network host -f ... --progress plain` (フラグは固定、`--memory` `--cgroup-parent` を足す口なし)。ビルド本体は **ホストの dockerd 内蔵 BuildKit** が実行 = helper コンテナの cgroup 外。
- **BuildKit RUN の cgroup**: moby の `newCgroupParent` は systemd driver だと `"<daemon.json cgroup-parent || system.slice>:docker:"` を BuildKit に渡し、RUN は `<slice>/docker-<id>.scope` (runc systemd 形式) になる。つまり **docker.service ではなく `system.slice` 直下の別 scope** で、通常コンテナと同じ親。daemon.json の `cgroup-parent` を変えると**通常コンテナとビルド RUN の両方**が同じスライスへ行く (ビルドだけ別スライスにはできない)。
- `docker build --cgroup-parent X` は frontend attr → `meta.CgroupParent` で個別に効く。ただし buildkit `executor/oci/spec.go` は「`.slice` を含み末尾 `:`」のときだけ systemd 形式 (`parent+id`)、それ以外は `/<parent>/buildkit/<id>` のパスにする。素の `foo.slice` を渡すと systemd driver 下でどう解釈されるかは未検証 (`foo.slice:docker:` と書けば systemd 形式)。**Coolify はこのフラグを渡せない**。
- **`docker build --memory`**: 旧 build API では RUN コンテナの cgroup に効いたが BuildKit は無視していた (discussion coolify#9085 の回答も「BuildKit 未対応」)。**moby/buildkit PR #6569 (2026-05-27 merge) で per-step の memory/cpu 制限が入り**、buildx は `--resource memory=2g` 形式 (各 RUN ステップ単位、ビルド全体の合算上限ではない)。ホストの Docker Engine 内蔵 BuildKit にこれが入っているかは未確認 (Coolify は固定コマンドなので結局使えない)。
- daemon.json の `cgroup-parent` は **SIGHUP 再読込対象に入っていない** (対象: debug, labels, live-restore, max-concurrent-*, default-runtime, runtimes, insecure-registries, registry-mirrors, shutdown-timeout, features 等) → 反映に dockerd 再起動が必要。systemd driver では値はスライス名 (`apps.slice`、パスではない)。既存コンテナは再作成まで旧親のまま。
- systemd 247 以降は cgroup2 を `memory_recursiveprot` 付きでマウント → `MemoryLow=` / `MemoryMin=` が配下サブツリーに再帰適用 (NEWS 247)。Ubuntu 22.04+ は該当。

## Why

Coolify は互換性のため run option を compose キーへ写像する方式で、未知オプションを素通しにしない。ビルドの隔離は Coolify の外 (dockerd / systemd / ホスト) でしかできない。

## How to apply

- Coolify の UI/API で per-app の cgroup 制御は不可。全アプリ共通の親は dockerd 再起動が必要 → 再起動禁止の環境では **稼働中の `docker-<id>.scope` に `systemctl set-property` (再起動不要、ランタイム即時)** と、ビルド用スコープの事後捕捉 (ビルド開始を検知して scope に MemoryMax を set-property) が現実解。
- ビルド専用 cgroup が欲しければ、ビルドを Coolify の外 (CI / build server 機能) に出す。公式ガイダンスも同じ (coolify.io/docs/troubleshoot/server/crash-during-build)。
- 未検証: 実機の `systemd-cgls` でビルド中の RUN scope の親を確認すること (本ノートはソース読みで、Docker Engine のバージョンは未確認)。
