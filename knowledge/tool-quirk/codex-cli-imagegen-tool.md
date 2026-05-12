---
title: Codex CLI 内蔵 imagegen ツール (gpt-image-1) の使い方
category: tool-quirk
tags: [codex, image-generation, gpt-image-1, chatgpt-subscription]
created: 2026-05-10
project: global
sources:
  - /Users/touri/.codex/plugins/cache/openai-primary-runtime/presentations/26.506.11943/skills/presentations/scripts/openai_generate_image.py
  - /Users/touri/.codex/plugins/cache/openai-primary-runtime/presentations/26.506.11943/skills/presentations/SKILL.md
  - codex features list (image_generation flag)
---

## Context

Codex CLI 経由で OpenAI Images API (gpt-image-1) を叩きたい場面。`OPENAI_API_KEY` 未設定、ChatGPT サブスク認証 (`auth_mode: chatgpt`) のみという前提でも実行可能。

## What

Codex CLI (v0.120.0 で確認) には **内蔵の `imagegen` ツール** がエージェント tool として組み込まれている。`OPENAI_API_KEY` を環境変数に置く必要はなく、ChatGPT サブスク認証のクレデンシャルでそのまま使える。

呼び出し条件:

1. `codex features enable image_generation` で feature flag を有効化 (デフォルトは `under development` で false)
2. `codex exec --sandbox workspace-write "...imagegen tool で〜を生成して..."` のように自然言語で依頼するだけ
3. 生成物は `~/.codex/generated_images/<session-id>/ig_<hash>.png` に保存される
4. 任意の保存先にコピーする指示も同じプロンプトで頼める

サイズ指定について: gpt-image-1 は `1024x1024` をリクエストしても `1254x1254` 等で返してくることがあるので、エージェントに `sips -z 1024 1024 <file>` でリサイズしてもらうのが安全。

出力 PNG はデフォルトで RGB (アルファチャンネルなし)。`background: transparent` を指示しても白背景 RGB になる場合あり。透過必須なら後処理で `magick` 等を使うか、白背景で運用する。

## Why

`presentations` プラグイン同梱の `openai_generate_image.py` は **「prompt メタデータを書き出すだけで API は叩かない」** ヘルパーで、本体は Codex agent の内蔵 tool。SKILL.md に "Use the Codex imagegen tool for image creation; this script only prepares the prompt and intended output path for the agent" と明記されている。

エージェント自身が tool として持っているため、ChatGPT サブスク経由のセッションでも OpenAI 側がモデレーションを通せば画像生成 API にアクセスできる (バックエンドはおそらく ChatGPT 内部の画像生成パイプラインと共通)。

## How to apply

```bash
# 1回だけ feature flag を有効化
codex features enable image_generation

# 生成 (1ファイルにつき codex exec を1セッション、並列実行可)
cd <project-root>
codex exec --sandbox workspace-write "Use your built-in imagegen tool to generate ONE image with these specs:
PROMPT: <英語で詳細に書く。日本語より英語の方が gpt-image-1 で安定>
SIZE: 1024x1024
FORMAT: PNG
QUALITY: high
After generation, copy to <absolute path> and resize to exactly 1024x1024 with sips. Confirm with ls -l."
```

注意点:
- `--ask-for-approval` フラグは `codex exec` には無い (top-level codex のみ)。`--sandbox workspace-write` で十分動く
- `codex exec` はデフォルトで `approval: never` で動くので非対話で完結
- 並列に5案生成する場合は `run_in_background: true` で5本同時に走らせると速い (1本あたり1〜2分)
- ChatGPT 内部 tool 経由なので、OpenAI のモデレーションで赤十字マーク等は弾かれることがある。プロンプトで明示的に "NO Red Cross, NO Star of Life" と書くのが安全
