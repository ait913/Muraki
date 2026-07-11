---
title: MCP server_instructions は二相化 (決定的オンボーディング + 能力パレット作業)
category: pattern
tags: [mcp, server-instructions, onboarding, capability-palette, agent-ux, prompt-design]
created: 2026-07-12
project: agent-hub
sources:
  - Muraki/projects/agent-hub/.designs/20260712-server-instructions-rewrite.md
  - Muraki/projects/agent-hub/agenthub/instructions.py
---

## Context

MCP の `server_instructions` (FastMCP `instructions=...`) は接続直後の AI に渡す自由文。
「固定ワークフローで縛らない = 能力パレット型」の思想で書くと、接続直後 (project_id/product_id
未知) の AI が入口の導線を失い「空気を読め」状態になる。Codex 独立レビューと Leader 診断が
「運用思想はあるが初回起動プロトコルが無い instructions」で一致した。

## What

- **二相化で「縛らない思想」と「初回は手順的であるべき」を両立させる**:
  - **オンボーディング相** = 所属先の特定 + 文脈取得 (`find_project → join_project → join_product
    → 返り値を読む`) を**番号付きの決定的プロトコル**で書く。迷わせない。
  - **作業相** = 文脈取得後の全活動は**能力パレット** (どの能力をいつ使うかは状況判断、縛らない)。
  - 相を貫く**不変条件は「約束」として別枠**に置く (能力=任意 とは別カテゴリの規範)。
- **instructions と各ツール docstring の責務分界**: docstring が高品質 (挙動・戻り値・エッジ
  ケース記述済) なら、instructions は docstring に無い上位 4 要素に絞る =
  ①全体像 ②初回導線 ③迷った時の優先順位 ④禁止事項。細則を instructions に再掲すると二重管理
  になり片方が陳腐化する。
- **初回導線は実ツールで裏付けてから書く**: 各ステップを実在ツール (返り値含む) で埋められる
  か照合する。例: 「product 特定」は `join_project` が参加済み product 一覧を返すことに依存 →
  架空手順を書かずに済む。
- **逆効果ワードを置換 (追記でなく)**: 「固定の手順はありません」「これらは義務ではなく能力
  です」は初回接続で導線と規範性を溶かす → 削除。

## Why

- 接続直後の AI の情報要求順は「これは何か → まず何をするか → 何を先に見るか → 何を守るか」。
  文化憲章的な情緒説明はツール選択の初速を鈍らせる。行動ポリシーとして書く。
- 能力パレット思想は「作業相は縛らない」が引き継ぐので、総括的な「義務ではなく能力」文言が
  無くても死なない。むしろ約束 (rationale 必須 / 決定を上書きしない / 他人の領域を見る) が
  「能力の例外」に見えると規範性が弱まる。

## How to apply

- MCP の instructions を書く/直すときは、まず「接続直後の AI は何を知らないか (id 未知等)」を
  起点にオンボーディング相を決定的プロトコル化。作業相はパレットのまま残す。
- docstring の質を先に確認し、細則はそちらに委ねて instructions を上位 4 要素に絞る。
- 受け入れ観点は文字列 grep で機械判定できる形にする: 存在検証 (初回導線に入口ツール名がある/
  約束が全て含まれる)・不在検証 (置換した旧文言が残っていない)・順序検証 (導線ツールが出現順)・
  長さ範囲。コード不変なら `import` して `len()`/`in`/`.index()` で純粋文字列テストできる。
