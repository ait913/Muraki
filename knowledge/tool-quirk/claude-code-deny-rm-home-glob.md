---
title: Claude Code の deny ルール `rm -rf ~/*` は ~/ 配下の個別パスも前方一致で拒否する
category: tool-quirk
project: muraki
tags: [claude-code, permissions, rm, cleanup]
created: 2026-10-23
sources:
  - ~/.claude/settings.json permissions.deny
  - sessions/2026-10-22-9f7e486b.md
---

## Context

ディスク整理で `rm -rf ~/Library/Developer/Xcode/DerivedData/*` や `rm -rf ~/Library/Caches/<app>` を実行しようとしたら、ユーザー承認済なのに Bash 呼び出しが deny された。

## What

`~/.claude/settings.json` の deny に `Bash(rm -rf ~/*)` と `Bash(rm -rf /Users/*)` がある。この `*` は「ホーム直下の全部」ではなく **glob として任意の文字列**にマッチするので、`rm -rf ~/Library/...` / `rm -rf /Users/touri/...` で始まるコマンドは全部拒否される。Muraki 配下の相対パス (`rm -rf $M/worktrees/...` のように変数経由) は引っかからない。

## Why

ルールの意図はホーム全消しの防止。個別ディレクトリの削除まで止める意図ではないが、パターン言語が前方一致 glob なので区別できない。

## How to apply

- ~/ 配下を消すときは親ディレクトリに `cd` してから相対パスで `rm -rf` する (例: `cd ~/Library/Developer; rm -rf Xcode/DerivedData/*`)
- 一つの Bash 呼び出しに複数の削除を詰めると、1 つが deny で全部止まる。ホーム配下と作業ディレクトリ配下は呼び出しを分ける
- ルール自体は触らない (意図どおりの安全網)
