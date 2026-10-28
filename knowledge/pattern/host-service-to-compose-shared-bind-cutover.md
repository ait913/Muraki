---
title: ホスト直走 (systemd + host nginx) のサービスを compose に移す — 同じ絶対パスの bind、保留起動で停止を数分に詰める、到達制限は edge 秘密で置き換える
category: pattern
project: global
tags: [docker-compose, coolify, systemd, nginx, traefik, sqlite, bind-mount, cutover, rollback, edge-auth, x-forwarded-for]
created: 2026-10-29
sources:
  - Muraki/projects/aisaba-platform/.designs/20261029-coolify-compose-migration.md §2, §4, §6, §8, §9
---

## Context

aisaba_platform の nexom 7 サービス (systemd、Python リテラル config、SQLite WAL、host nginx の `cloudflare_only` で到達制限) を Coolify の raw compose に移す設計で出た、汎用の判断。

## What

1. **データは同じ絶対パスに bind mount し、旧と新は同時に動かさない。ビルドと起動確認は停止前に「保留起動」で済ませる。** 新コンテナは env (`NEXOM_HOLD=1` を compose の既定にする) の間はサービスを起動せず app コードも import しない (= DB を開かない) 形にし、healthcheck も保留中は成功にする。停止前に保留のまま deploy して mount・network・healthcheck を確かめる → 旧を停止 → 全 SQLite に `PRAGMA wal_checkpoint(TRUNCATE)` + `quick_check` → tar → env を 0 にして redeploy → 内部 smoke → 前段切替。ダウンタイムは停止〜切替の数分。並走 (旧と新が同じ DB を書く) は安全性を本番書き込みの後でしか判定できず、ファイルログの RotatingFileHandler が別プロセス群の間で rename を取り合うので採らない (aisaba 2026-10-29、Codex 指摘)。uid / gid を揃えた bind なら、旧に戻してもコンテナが書いた分はそのまま読まれる
2. **compose の bind は long 構文 + `bind.create_host_path: false`。** short 構文は source が無いと root 所有の空ディレクトリを作って黙って起動する (typo で空 DB を作る経路)。long 構文の既定は「無ければ失敗」
3. **ライブの config を書き換えず、コンテナ用の写しを別の場所に作り、ファイル単位で元と同じパスに ro mount する。** 写しの置換は AST で行範囲を取って key 単位 (複数行 tuple に正規表現を当てない)、置換 key 以外は出力しない (同じファイルに秘密がある)。**symlink で差し込む方式は `Path(__file__).resolve()` で導出しているパスが symlink 先に化ける** ので使わない
4. **「loopback + 送信元 IP の allow」で守っていた到達制限は、コンテナ化で必ず崩れる** (共有 reverse proxy = Traefik は全 network に attach しているので、どのコンテナからでも Host ヘッダ付きで届く)。前段が付ける edge 秘密ヘッダを内側の nginx が `map` で照合して 404、上流へは空値で渡さない。秘密は env + envsubst でなくホストのファイル 1 本の ro bind にすると read_only rootfs のまま済む
5. **クライアント IP は前段の信頼段数でなく、edge 検査を通った要求の `CF-Connecting-IP` から内側の nginx が `X-Forwarded-For` を 1 要素で作り直す** (アプリの trusted proxy 数 = 1)。共有 proxy (Traefik) の `trustedIPs` を触らずに済み、前段の構成が変わっても (host nginx 廃止など) 段数を直さなくてよい
6. **サービス間呼び出しの宛先・待受は固定 IP で、待受は「正当な呼び出し元がいる network の IP だけ」に bind する。** 送信元 IP の完全一致ガード (AuthService の `ALLOWED_CLIENTS` 等) を持つサービスは呼び出し側の IP 固定が必須。DNS 名は Coolify 等が足す別 network 側の IP を返し得る
7. **共有 proxy の router は最初から本番 Host で出してよい** (前段の vhost を書き換えるまで外から届かないなら)。label を後から足すための redeploy は要らない
8. **nginx の healthcheck 用 location を `allow 127.0.0.1; deny all; return 200;` で書かない** — `return` は rewrite 段で access 段より先に効くので allow/deny が成立しない。`listen 127.0.0.1:<別 port>` の専用 server に分ける
9. **ファイル単位の bind は inode を掴む。** ホスト側を `os.replace` / エディタで置き換えたら、コンテナを再作成して中身の sha256 を確かめる

## Why

ホスト直走の前提 (loopback、ファイルパス直書き、前段 1 段の XFF) を「コンテナでどう再現するか」が核で、データを動かさない (bind) 選択がロールバックの安全性と切替手順の単純さを同時に決める。

## How to apply

- 切替手順は「読み取り (DB と `-wal` / `-shm` のファイル単位の所有者、ACL、userns、SQLite 版) → 秘密と config の写し → 使い捨てリソースで probe (本番パスを ro で mount、stat から書き込み可否を計算) → 本番リソースを保留起動 → 旧停止 → checkpoint + tar → 保留解除 → 内部 smoke → 前段 proxy の reload → 外形確認 → N 日後に旧の片付け」
- 受入は「到達不能」でなく拒否の文言 (404 / 403) + 負のコントロール (同じ要求を正規の経路・正規の送信元から出すと通る)。前段に別の拒否層 (Traefik の ipAllowList 等) があるなら、検査したい層の直前から叩く
