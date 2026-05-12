---
title: Claude Haiku 4.5 API 仕様 (2026年5月時点)
category: library
tags: [anthropic, claude, llm, api, tool-use]
created: 2026-05-11
project: global
sources:
  - https://platform.claude.com/docs/en/docs/about-claude/models
  - https://platform.claude.com/docs/en/docs/build-with-claude/tool-use/overview
  - https://www.npmjs.com/package/@anthropic-ai/sdk
  - https://devtk.ai/en/blog/claude-api-pricing-guide-2026/
---

## Context
秘書系・チャット・軽量エージェント用途で Claude を使う際の最新スペック。Haiku 4.5 をデフォルトに据える時の参照。

## What
**Claude Haiku 4.5** (2026年5月時点で現役):
- Model ID: `claude-haiku-4-5-20251001` / alias `claude-haiku-4-5`
- Context window: **200k tokens** (Sonnet 4.6 / Opus 4.7 はどちらも 1M)
- Max output: 64k tokens
- Pricing: **$1 / 1M input、$5 / 1M output**
- Extended thinking: **Yes**
- Adaptive thinking: **No** (Sonnet 4.6 / Opus 4.7 のみ)
- Priority Tier: Yes
- Knowledge cutoff (reliable): Feb 2025
- Vision: Yes (全 Claude 4 系)
- Tool use system prompt cost: auto/none 346 tokens、any/tool 313 tokens

**比較材料**:
- Sonnet 4.6: $3/$15、1M context、adaptive thinking 有
- Opus 4.7: $5/$25、1M context、最強だが遅い
- Gemini 2.5 Flash: $0.15/output (Haiku 4.5 比 6.7x 安い)、Gemini 3 Flash は $0.5/$3

**SDK**: `@anthropic-ai/sdk` 最新 v0.95.x。`npm i @anthropic-ai/sdk`。

```ts
import Anthropic from "@anthropic-ai/sdk";
const client = new Anthropic();
const resp = await client.messages.create({
  model: "claude-haiku-4-5",
  max_tokens: 1024,
  tools: [{ name: "get_weather", description: "...", input_schema: {...} }],
  messages: [{ role: "user", content: "..." }],
});
// resp.stop_reason === "tool_use" → tool_use block を取り出して実行 → tool_result を返す
```

`strict: true` を tool 定義に付けると schema 厳密一致が保証される (2026 新機能)。

## Why
- Haiku 4.5 は「near-frontier 知能 + 最速 + 最安」のスイートスポット。秘書系の reply / 軽い tool routing には十分。
- ただし adaptive thinking が無いので、深い推論が必要なステップだけ Sonnet 4.6 へエスカレートする 2 段構成が現実的。
- Gemini 2.5/3 Flash は明確に安いが、tool 安定性・指示追従の質では Anthropic 系の方が安定 (体感)。コスト最重要なら Gemini、品質重視なら Haiku。

## How to apply
- tomori のような単一ユーザー秘書アプリは Haiku 4.5 をデフォルト、複雑な対話だけ Sonnet 4.6 にルーティング
- context 200k は会話ログ全件保持には十分だが、Phase 2 で Gmail/Calendar 全文を投げると不足する → Sonnet 4.6 (1M) を併用
- alias `claude-haiku-4-5` は dateless だが pinned snapshot なので、本番では具体 ID `claude-haiku-4-5-20251001` を直接指定するのが安全
- tool 定義は `strict: true` を必ず付ける (JSON 不正で再呼び出しになるロスを減らせる)
