---
title: auditd は `-w <path>` の path が 1 つ無いだけでそこで読込を止め、以降のルール (99-immutable の `-e 2` を含む) が載らない。rules に `-c` を入れ、受入は `auditctl -s` の enabled と `auditctl -l` の本数で取る
category: gotcha
project: global
tags: [auditd, augenrules, auditctl, immutable, coolify, boot-order]
created: 2026-10-29
sources:
  - aiserver2 での実走 (sessions/2026-10-29-b45758d0.md 87)
  - projects/aiserver/ops/audit/aiserver.rules
---

## Context

aiserver2 で `rules.d/50-aiserver.rules` (watch 20 本 + syscall 12 本) と `99-immutable.rules` (`-e 2`) を置いて再起動したところ、`systemctl is-active auditd` は active なのに `auditctl -s` は `enabled 1`、`auditctl -l` は 8 本だけだった。journal には `augenrules: There was an error in line 13 of /etc/audit/audit.rules` / `No rules`。

## What

- `auditctl -R` (augenrules の実体) は **エラー行に当たるとそこで読込を打ち切る**。既定では続行しない。`-D` 直後に **`-c`** を置くとエラーを飛ばして続行する
- ENOENT の典型は「起動時にはまだ無い dir」。Coolify は `/data/coolify/ssh/keys/` と `mux/` を**起動ごとに作り直す** (auditd の起動 10 秒後)。配置時の `augenrules --load` は dir があるので通り、再起動で初めて落ちる。install script が「存在しない path の行を落とす」仕組みでも、配置時点の存在しか見ていないので防げない
- auditctl のエラー行番号はファイルの行番号と一致しない (コメント / `-D` を数えない) ので、行番号でなく `-w` の path を `sudo test -e` で総当たりする。ただし **`ais` で test すると root 専用 dir が全部 MISSING に見える** ので sudo で
- `-e 2` が効いている間は `augenrules --load` が拒否される。rules を直したら 01:00 の自動再起動に乗せる (aiserver2)

## Why

systemd の unit 状態とカーネル側の audit ルールは別物。ルール 0 本でも auditd 自身は正常に動く (ログも流れる) ので、service の状態を受入条件にすると見えない。

## How to apply

- rules の先頭 (`-D` の次) に `-c`
- 起動時に作り直される dir は watch しない。残り続ける親 dir を `-w` する (`/data/coolify/ssh/`)
- 受入: `sudo auditctl -s | grep enabled` が `2`、`sudo auditctl -l | wc -l` が期待本数、`journalctl -b -u auditd | grep -E "error in line|No rules"` が空。再起動後にもう一度
