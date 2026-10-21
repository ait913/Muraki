---
title: Bash ツールは zsh — 変数の単語分割が起きないので for ループは bash -c で包む
category: tool-quirk
project: muraki
tags: [claude-code, bash-tool, zsh, scripting]
created: 2026-10-22
sources:
  - Muraki/sessions/2026-10-22-acd89e01.md
---

## Context

Claude Code の Bash ツールはこの機体では **zsh** で動く。bash のつもりで `for x in $VAR` や `set -- $pair` を書くと、zsh は変数を単語分割しないため**ループが 1 回しか回らない / 空文字が渡る**。2026-10-22 に 2 回踏んだ (Coolify の deployment uuid を 2 行入れた変数でポーリングしたら `curl: (3) URL rejected: Malformed input` のまま 10 分空回り、`set -- $pair` で全フィールドが空)。

## What

- `DEPS=$(... | jq -r '.[]')` のような改行区切りの変数を `for d in $DEPS` で回すと zsh では **1 要素** として扱われる
- `set -- $pair` も分割されず `$1` に文字列全体が入る
- glob 展開も `nomatch` が既定で、`--include=*.ts` のような引数が「no matches found」で**コマンドごと失敗**する

## Why

zsh は `SH_WORD_SPLIT` が既定で off。bash 互換の挙動は `bash -c '...'` の中でだけ得られる。

## How to apply

- 複数行の変数を回す / `set --` を使う / glob を含むループは **`bash -c '...'` で包む**か、スクリプトファイルに書いて `bash file.sh` で実行する
- `--include='*.ts'` のような grep 引数は**クォート**する
- 長いポーリングは background にし、出力に進捗が出ないまま数分経ったら変数展開を疑う
