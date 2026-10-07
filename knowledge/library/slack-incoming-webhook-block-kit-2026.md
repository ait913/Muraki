---
title: Slack Incoming Webhook の Block Kit 制約 (色帯は attachments、折り畳み無し)
category: library
tags: [slack, incoming-webhook, block-kit, attachments]
created: 2026-10-07
project: global
sources:
  - https://docs.slack.dev/legacy/legacy-messaging/legacy-secondary-message-attachments/
  - https://docs.slack.dev/reference/block-kit/blocks
  - https://docs.slack.dev/tools/slack-github-action/sending-data-slack-incoming-webhook/
---

## Context
Webhook 通知を text のみから Block Kit に作り直す前の調査 (wasawasa)。

## What
- 色帯は `attachments[].color` (good / warning / danger / hex) でしか出せない。attachment に `blocks` を入れられるので `{text(fallback), attachments:[{color, blocks}]}` が定石。
- 上限: メッセージ 50 blocks、header 150 字 (plain_text のみ)、section text 3000、fields 10 個 x 2000 字、context 10 要素、actions 25 要素、button text 75 字 / url 3000 字、attachments 100。
- Webhook は channel / username / icon を上書きできない。link 付き button (`url` + `action_id`) は Webhook で使える (公式 slack-github-action の例)。
- 折り畳み UI は Webhook に無い。attachment の `text` は 700 字以上または改行 5 個以上で Slack クライアントが自動的に畳む。attachment 内 `blocks` の畳み条件は一次情報なし。
- `@slack/types` の latest は 3.2.0 (MIT、node>=20、`KnownBlock` / `MessageAttachment`)。型の誤りは tsc で出るが文字数上限は検出されない。

## Why
Slack が color に block 代替を用意していないため、legacy の attachments を併用する。

## How to apply
色帯付きの通知は attachments 内 blocks で組み、上限は自前関数で切り詰めてテストする。見た目は実 Slack で最終確認 (Block Kit Builder は Web UI のみ)。詳細: projects/wasawasa/.knowledge/research-slack-block-kit.md
