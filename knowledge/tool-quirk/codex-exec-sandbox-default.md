---
title: "codex exec はデフォルト read-only サンドボックス、scaffolding 系は --full-auto 必須"
category: tool-quirk
project: global
tags: [codex, codex-exec, sandbox, scaffolding, developer-agent]
created: 2026-05-10
sources:
  - "codex --version: codex-cli 0.120.0"
  - "codex exec --help"
---

## Context
Developer (Codex) に空 worktree から Vite/React プロジェクトを scaffold させたら、`apply_patch` が `writing is blocked by read-only sandbox; rejected by user approval settings` で全部弾かれた。

## What
`codex exec` の `--sandbox` フラグは未指定時 **read-only** になる。worktree 内へのファイル作成・編集が全部拒否される。

選択肢:
- `--sandbox read-only` (デフォルト) — 読み取り専用
- `--sandbox workspace-write` — workspace 内のみ書き込み可、ネットワークは制限あり
- `--sandbox danger-full-access` — 全部許可
- `--full-auto` — `--sandbox workspace-write` のショートカット
- `--dangerously-bypass-approvals-and-sandbox` — 完全バイパス (`gemini --yolo` 相当、CLAUDE.md で禁止)

## Why
Codex CLI は安全寄りデフォルト。インタラクティブモード (`codex` 単体) は許可ダイアログを出すが、`codex exec` (非対話) は許可待ちできず即拒否する。

CLAUDE.md で禁止されているのは `codex apply` と `gemini --yolo` 系のみ。`--full-auto` (= workspace-write) は禁止対象外。

## How to apply
- **空 worktree から実装させるとき**: 必ず `--full-auto` を付ける
- **既存コードの読み取り解析・レビュー**: デフォルト (read-only) のまま
- **既存コードに微修正**: `--full-auto`
- **完全バイパス (`--dangerously-bypass-approvals-and-sandbox`) は使わない** — Muraki ではユーザーが明示許可しない限り禁止に倣う

Developer agent (`~/.claude/agents/developer.md`) のテンプレに `--full-auto` を入れておくと再発防止になる。現状は付いていない。

### Developer agent ハングの別問題
今回の検証で発覚: `developer` subagent が `codex exec` を `Bash run_in_background=true` で起動した後、完了通知を待ち続けて自分が先にタイムアウト終了する事象あり。Leader 側で直接 codex を回す方が確実なケースがある。本症状は `developer.md` 側の改善余地として記録。
