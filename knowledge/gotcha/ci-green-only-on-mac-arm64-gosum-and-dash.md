---
title: Mac (arm64 / bash) で全緑でも GitHub Actions (amd64 / dash) で落ちる 2 パターン — go.sum の amd64 専用依存と ${VAR:?} の終了コード
category: gotcha
project: ais-pass
tags: [github-actions, go-modules, go.sum, arm64, amd64, dash, posix-sh, ci]
created: 2026-10-30
sources:
  - Muraki/sessions/2026-10-29-b45758d0.md (99)
  - ais-pass CI runs 2026-10-26 20:31 〜 2026-10-29 22:48 (21 連続 failure)
---

## Context

ais-pass の GitHub Actions CI が Go 書き直しの初 push (2026-10-26) から **21 回連続で失敗**していたのに、ローカル (Mac arm64) では契約テスト含め全緑だったので 3 日間誰も気付かなかった。原因は 2 つとも「Mac と Ubuntu ランナーの差」。

## What

1. **go.sum の amd64 専用依存の欠落**: `golang.org/x/crypto` の `chacha20poly1305_amd64.go` だけが `golang.org/x/sys/cpu` を import する。nested module `test/go.mod` に x/crypto を足したとき Mac (arm64) で `go test` を回しただけだと x/sys は解決されず go.sum に載らない。CI (amd64) では `missing go.sum entry for module providing package golang.org/x/sys/cpu` で `[setup failed]`。**`go mod tidy` は全 GOOS/GOARCH を見る**ので tidy していれば入っていた
2. **`${VAR:?}` の終了コード**: 未設定時に bash (macOS の `/bin/sh`) は exit 1、dash (Debian / Ubuntu の `/bin/sh`、postgres 公式 image も) は exit 2。テストが「未設定なら exit 1」を要求していたので CI だけ落ちた

## Why

- `go test` はその場の GOOS/GOARCH で必要な依存しか検証しない。go.sum の完全性は `go mod tidy -diff` でしか確かめられない
- `${VAR:?}` のメッセージと終了コードは POSIX が「非ゼロ」としか決めていない

## How to apply

- 依存を足したら必ず `go mod tidy` (nested module は各ディレクトリで)。CI に `go mod tidy -diff` (Go 1.23+) を入れて差分ゼロを要求する
- 本番 image が Debian 系なら sh スクリプトの終了コードを `${VAR:?}` に任せず `if [ -z "${VAR:-}" ]; then ...; exit 1; fi` と明示する。手元で確かめるなら `docker run --rm -v "$PWD:/w" debian:bookworm-slim sh /w/script.sh`
- **CI が赤いままの PR / push を重ねない**。赤の原因が 1 行なら 10 分で直る。放置すると「赤が普通」になり、本物の失敗 (この後に隠れていた N10) も見えない。リポジトリの CLAUDE.md の「デプロイ」節に「CI が緑であること」を受入に入れる
