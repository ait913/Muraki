---
title: MCP Apps iframe のマルチテナント文脈解決 — 通知非依存の user スコープ解決 + project pin
category: pattern
project: dandan-app
tags: [mcp, mcp-apps, iframe, multitenant, chatgpt, ui-context]
created: 2026-07-07
sources:
  - Muraki/projects/dandan-app/.designs/20260707-amano-ux-remote.md §5
  - dandan-mcp ui/bridge.js:261 (ChatGPT 通知不達の実測コメント)
---

## Context

シングルテナント MCP サーバー (MCP Apps iframe UI 付き) をマルチユーザー化するとき、「グローバル最新」「グローバル名簿」型の文脈参照をどう変換するか。iframe は「どのテナント文脈を描画すべきか」を自力で知る必要がある。

## What

- **ホスト通知 (`ui/notifications/tool-input`/`tool-result`) は文脈受け渡しに使えない**: ChatGPT はモデル発ツール呼び出しを iframe に通知しないことがある (dandan-mcp が実測、ポーリングで回避した実績)。opener ツールの引数を通知で受け取る設計は不成立。iframe は引数なしの context 取得ツール (Bearer から user 解決) を自分で呼んで bootstrap する。
- グローバル参照の user スコープ射影 (dandan で採用した 3 分解):
  1. 「最新 plan」→ **caller がアクセス可能な集合内の最新** (自作 unbound ∪ pin project 内 → fallback で参加 project 全体)。`plan_id 省略可` の使い勝手を殺さずに越境を封じる。
  2. 「グローバル名簿/設定」→ project スコープ + **文脈 project 解決** (明示 owner/repo 引数 → 最新 plan の project → user ごとの project pin、の優先順)。
  3. 「最後に使った repo」→ user ごとの **project pin** (`workspace_contexts(user_id PK, project_id)`)。owner/repo を明示して project 解決に成功したツールだけが pin を書く。
- 既存ツールのシグネチャは変えない。書き込み系で project が必須になる場合のみ **optional owner/repo を追加** (旧呼び出し形は文脈 fallback で動き続ける)。
- pin 読み取りでは membership を再検証し、失敗時は pin を削除して「文脈なし」に落とす (他テナント情報を漏らさない)。複数チャット並行は last-write-wins (UI が文脈 repo を常時表示していれば誤 pin は可視)。

## Why

MCP セッションは再接続で消え、ホストの会話 ID はサーバーに届かない。永続で user に安定に紐づくのは DB だけ。かつ通知不達ホスト (ChatGPT) では「引数なしで呼べる context ツール + サーバー側の決定論的解決」だけが iframe bootstrap の信頼できる経路。

## How to apply

- 不在と越境は同一エラー表現にする (存在有無を漏らさない)。UI が既存のエラー文字列マッチ (例: "store: not found") に依存しているなら、その文字列契約ごと保存する。
- 解決優先順位 (明示引数 → 最新 plan 由来 → pin → なし) を設計 doc に決定論で書き、負系 (他人の unbound plan を掴まない等) をテストで固定する。
- `_meta.ui` は opener ツールにだけ付け、context 取得ツールには付けない (再フェッチのたびにホストが新 UI を開こうとするのを防ぐ)。
