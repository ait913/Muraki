---
title: "Codex CLI / Gemini CLI を並列レビューに使うときの癖"
category: tool-quirk
project: global
tags: [codex, gemini, cli, parallel, review]
created: 2026-05-08
sources:
  - https://github.com/openai/codex
  - https://github.com/google-gemini/gemini-cli
---

## Context
複数 LLM で同じコードを独立レビューさせ、結果を JSON で集約したい。

## What
- **codex exec**:
  - ChatGPT account auth では `-m` でモデル指定**不可**。デフォルト = OpenAI 側で決まる
    (現状 gpt-4o 系が出ている観測)。
  - 並列実行は `~/.codex/` ステート競合に注意。`--session-id <UUID>` を毎回別にする。
  - JSON 出力: `--json` で JSONL ストリーム。`--output-schema <path>` で構造化指定可。
  - レート: ChatGPT 利用枠 (Plus 等) の reasoning 時間を消費。
- **gemini -p**:
  - `-p` = `--prompt` 非対話。モデル指定は `-m` / `--model`。
  - JSON: `-o json` / `--output-format json` で 1 オブジェクト返却。
  - 並列は `--worktree` (`-w`) でセッション分離可。
  - **2026-05 現在 `gemini-3-flash-preview` が capacity exhausted で 429 多発**。
    リトライ 5 回後でもエラー出ることあり。**バックグラウンド実行 + 待機**前提で組む。
- **使い分け**:
  - Web 検索でフレッシュ情報 → Gemini (内部で web search ツールを呼ぶ)
  - 公式ドキュメント正確引用 → Codex (URL 引用が安定)
  - 並列 (JSON 集約) は両者出力フォーマットが異なる前提で正規化レイヤを挟む

## Why
- Gemini の 429 は単発再試行で解消しないことが多く、長時間ジョブ向きではない。
- Codex は出典 URL を比較的安定して付ける (Gemini は引用無しの主張をすることがある)。

## How to apply
- リサーチでは Gemini と Codex を**並列起動 (run_in_background)** し、
  Gemini が capacity 出した場合に Codex 結果のみで先に進める設計にする。
- 並列レビューでは `--session-id` (Codex) / `-w` (Gemini) を必ず渡す。
