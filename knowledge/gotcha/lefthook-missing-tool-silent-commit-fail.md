---
title: lefthook の pre-commit が「ツール未インストール」で commit を無言中断する
category: gotcha
project: omatase (lefthook を使う PJ 全般)
tags: [lefthook, git, commit, golangci-lint, oxfmt, pnpm, node_modules, developer, worktree]
created: 2026-07-23
sources:
  - omatase lefthook.yml
  - 実測 (2026-07-23 backend heart マージ時)
---

## Context

omatase は lefthook の pre-commit で `golangci-lint`(*.go) / `oxfmt`・`oxlint`(*.md,*.ts 等) /
`gofmt`(*.go) を走らせる。**必要ツールが環境に無いと commit が失敗するが、症状が分かりにくい。**

## What

`git commit` が **exit 128 / 254 で無言中断**し、変更が **staged 止まり**になる。
git log に反映されず、後で `git merge` すると **"Already up to date"** になって「なぜマージできない?」と混乱する。

実測で踏んだ 2 パターン (2026-07-23):
1. **`golangci-lint: command not found` (exit 127)** — この環境に golangci-lint 未インストール。
   `.go` を含む commit が pre-commit で必ず落ちる。(`~/go/bin` が PATH 外だと `go install` 後も同じ)
2. **`pnpm exec oxfmt` → `Command not found` (ERR_PNPM_RECURSIVE_EXEC_FIRST_FAIL)** — **worktree/repo に
   node_modules が無い**。`.md`/`.ts`/`.tsx`/`.json`/`.yaml` を含む commit が全部落ちる
   (glob に `md` も入っているので **doc-only の commit すら**ブロックされる)。

lefthook の出力は `🥊 <tool>` (ラン/失敗) と `✔️ <tool>` (成功) で、tail truncate すると
`command not found` の行が見えず「hook 名だけ出て commit されない」ように見える。

## Why

`.gitignore` で node_modules 除外・worktree は node_modules を共有しない・iCloud evict で消える
(→ [[env_icloud_evict_hangs]]) 等で node_modules が欠落しやすい。golangci-lint は go 管理外の別バイナリで
`go build` は通っても未インストールなことがある。lefthook はどれか 1 コマンドが非ゼロ終了すると commit を止める。

## How to apply

- **go を含む commit**: `golangci-lint` を入れて PATH を通す。
  `go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest` → `~/go/bin` へ。
  commit は `PATH="$HOME/go/bin:$PATH" git commit ...`(lefthook は呼び出し元 env を継承)。
- **md/ts 等を含む commit**: その worktree/repo で `pnpm install` 済みを確認 (`ls node_modules`)。
  main worktree と feature worktree は **別々に** node_modules が要る (worktree は共有しない)。
- **commit が通らない時の切り分け**: `git status` で staged 止まりか確認 →
  full output で `git commit`(tail しない) → `🥊` の行に `command not found` が無いか見る。
- **緊急回避**: doc-only や「既に別手段で検証済み」の変更なら `git commit --no-verify` で hook を飛ばす
  (ただし常用しない。ツールを入れて gate を実際に通すのが正)。
- **恒久**: `~/go/bin` を PATH に追加、各 worktree で `pnpm install` を初手で走らせる。
