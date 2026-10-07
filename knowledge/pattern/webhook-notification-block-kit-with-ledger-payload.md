---
title: Webhook 通知のカード化は「既定 = 構造化カード / カスタム = 文字だけ」+ 送った本文を台帳に保存
category: pattern
tags: [slack, incoming-webhook, block-kit, notification, outbox, template]
created: 2026-10-07
project: global
sources:
  - projects/wasawasa/.designs/20261003-deploy-mcp-slack-responsive.md §9 ((11))
  - knowledge/library/slack-incoming-webhook-block-kit-2026.md
---

## Context
文字テンプレートで Slack Incoming Webhook に通知していたシステム (wasawasa) を、GitHub 通知風の色帯つきカード (Block Kit) に作り直した。既存資産は「ユーザーが書ける文字テンプレート」「投入時に描画して保存する配送台帳 (outbox)」「再送」「台帳の text を完全一致で見るテスト」。

## What
- **形式**: `{ text: <1 行の fallback>, attachments: [{ color, fallback, blocks }], unfurl_* : false }`。色帯は `attachments[].color` でしか出ないので attachment は常に 1 個、blocks は全部その中。top-level `text` は通知バナー用の 1 行 (改行なし・空にしない・300 字)
- **レイアウトは 5 段固定**: header (絵文字 + 短い題) → fields (`*ラベル*\n値`、Slack が 2 列に詰める、空の値は出さない) → メモ (行数と文字数で切って「続きは本体で」リンク) → link ボタン (URL を検査して不正なら出さない) → context (実行者 · 時刻 · 小さなラベル)。kind ごとの差は「題・色・fields の列・ボタン」の表 1 枚で表せる
- **テンプレ互換**: ルールのテンプレートが NULL (既定) ならカード、文字列なら従来の文字だけ。カスタム文面をカードに混ぜる DSL は作らない。fields は既存のテンプレ変数から組む (同じ Event で文字とカードの値が食い違わない)
- **台帳に `payload jsonb` (送った本文そのもの)** を足し、`text` は fallback として残す。送信は `payload ?? {text}` (旧行・rolling 中の旧コンテナの行は text から)。再送は payload をそのまま送る (再描画しない)
- **切り詰めは escape の前、コードポイント単位**、上限検査 (`assertPayloadLimits`) は純関数 + unit テスト。`@slack/types` は型 (構造) しか守らない
- **同じ tx で 2 つの Event が出る経路** (例: アップロード完了 + ビルド登録) は、ルール単位でなく Event 単位で片方を投入しない (どのルールの組でも 1 通)

## Why
- 色帯の代替が無い Slack の制約に合わせると attachment 構造は一択。カスタム文面のカード化は「どこが利用者の文面か」が曖昧になり、小さな言語を抱える
- 送信時に再構築すると、レイアウト変更後の再送が「送った物と違う物」になり、参照先 (リリース等) が消えると組めない。描画済み保存の方針を payload に延ばすのが最小
- Block Kit の文字数上限は型で検出できず、escape 後に切ると `&amp;` を割る

## How to apply
- 通知のリッチ化では先に「既定 / カスタム」の境界と「台帳に何を保存するか」を決め、レイアウトは表 1 枚 + JSON 例 (参照実装で実走して生成) を設計 doc に置く。Reviewer は例と deep equal で見る
- 既存テストの移行は「テンプレートが NULL のルールの配送の text を見ているもの」を軸に grep する (kind 別に探すと Phase をまたいだ smoke / gate-fixes を取りこぼす)
- link ボタンは Webhook でも開けるが、未設定アプリの警告が出る可能性 (未確認) があるので、ボタン ⇄ mrkdwn リンク行を定数 1 つで切り替えられるように設計しておく
- 見た目の最終確認は実 Slack (人の操作) で。テスト送信は「本番で一番重要なカードの見本」を送るようにするとゲートとして機能する
