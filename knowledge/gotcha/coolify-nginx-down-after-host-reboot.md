---
title: Coolify の API/UI が 502 — ホスト再起動後にコンテナ内 nginx だけ s6 で down のまま
category: gotcha
tags: [coolify, s6, nginx, onprem, reboot, 502]
created: 2026-10-20
project: global
sources:
  - sessions/2026-10-20-51ff8610.md
---

## Context
bloom 0.2.4 のリリース作業で Coolify API (`$COOLIFY_API_BASE/applications/<uuid>/envs`) が Cloudflare の `error code: 502` を返し、`coolify.aisaba.net` の UI も 502。wasawasa の `coolify_check` も「接続できない」。一方で配信中のアプリ (bloom-api 等) と `coolify-proxy` (Traefik) は正常。

## What
- `docker ps` では `coolify` コンテナが `Up 10 hours (unhealthy)`。healthcheck は `curl 127.0.0.1:8080` が `Failed to connect` で failing streak 7000 超 (= 01:00 JST の定期ホスト再起動 `ais-auto_reboot.timer` 以降ずっと)
- `docker top coolify` に php-fpm / horizon / scheduler / reverb はいるが **nginx のプロセスが無い**。`s6-supervise nginx` は居る
- `/run/service/nginx/down` ファイルが再起動時刻 (16:00Z = 01:00 JST) で存在し、`s6-svstat` は `down (not started yet)`。`nginx -t` は OK (設定は壊れていない)
- 復旧は **コンテナ内の s6 で nginx を上げるだけ**:
  ```sh
  ssh -p 51000 ais@192.168.3.17 "sudo docker exec coolify /command/s6-svstat /run/service/nginx"
  ssh -p 51000 ais@192.168.3.17 "sudo docker exec coolify /command/s6-svc -u /run/service/nginx"
  # → up (pid …), ready。外からの API も即 200
  ```
  s6 のバイナリは `PATH` に無く `/command/` 配下 (`s6-svc` と打つと executable not found)
- Coolify のスケジューラやデプロイジョブは nginx 無しでも動いているので、「UI/API だけ死んでいる」状態

## Why
serversideup の php イメージは s6-rc で nginx を立ち上げる。ホストの定期再起動でコンテナが起動し直した際、何らかの理由で s6-rc が nginx を `down` のまま放置した (1 回限りの事象かは不明。設定ファイルは正常で、手動 up で即復帰したので設定起因ではない)。healthcheck が unhealthy でも Docker は自動再起動しない (restart policy は crash 時のみ)。

## How to apply
- Coolify API/UI が 502 で `coolify-proxy` と各アプリが生きているなら、まず `docker ps` の `coolify` の health と `docker top coolify | grep nginx` を見る。nginx が居なければ上の `s6-svc -u` で復旧 (コンテナ restart より軽い、Docker daemon restart は禁止 [[feedback_no_docker_daemon_restart]])
- Tunnel 経由の `ssh aisaba` は Cloudflare Access の OTP が要る。家にいるなら LAN `ssh -p 51000 ais@192.168.3.17` が BatchMode で通る
- 翌日以降の 01:00 再起動でも再発するなら、ホスト側に「`coolify` が unhealthy なら `s6-svc -u`」の timer を足すか、Coolify の issue を探す (`coollabsio/coolify` で "nginx down after reboot")
