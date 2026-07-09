---
title: 状態遷移・権限チェックは先行 read でなく atomic UPDATE の WHERE に置く (asyncpg)
category: gotcha
project: agent-hub
tags: [asyncpg, postgres, concurrency, toctou, transaction, optimistic-lock, security]
created: 2026-07-09
sources: [agent-hub Slice1/2 reviewer, agent-hub Codex 白箱レビュー 2026-07-09]
---

## Context

AgentHub (Python/asyncpg/Postgres の MCP) の実装で、**同じ family のバグを3回踏んだ**。stateless・複数レプリカ・複数 AI が同時接続する前提だと「先に read して Python で判定 → 後で write」は必ず競合で壊れる。

## What

同 family の3事例:

1. **raise で副作用が巻き戻る** (`rotate_refresh_token`): family 全 revoke の `UPDATE` と `raise ...Reused()` が同一 `async with conn.transaction():` 内 → raise でトランザクションが巻き戻り revoke がロールバック (RFC9700 破れ)。→ 副作用を確定させてから raise はブロック外へ。
2. **TOCTOU で他人の行を更新** (`update_task_status`): owner を先行 `SELECT` で Python チェック → `UPDATE ... WHERE id=$1` だけで status 更新。read→write の間に owner が変わると他人の Task を書き換える。
3. **非原子な状態遷移で不変条件が破れる** (Decision supersede): 新 accept 時に旧を `UPDATE ... WHERE status='accepted'`。0 行(既に別の superseder が置換済み)を無視 → 「1旧:1superseder」不変が破れ二重 accepted。

## Why

MCP の tool は複数クライアントが並行に呼ぶ。`SELECT`→(Python 判定)→`UPDATE` の間に別リクエストが状態を変える窓が必ず開く。in-process ロックは stateless_http + 複数レプリカで効かない。Postgres の行ロック/条件付き UPDATE だけが原子性を保証する。

## How to apply

- **権限条件・version・前提状態を、先行 read でなく `UPDATE ... WHERE` に全部畳み込む**。例: `UPDATE tasks SET status=$s, version=version+1 WHERE id=$1 AND version=$v AND (owner_user_id=$me OR (status='cancelled' AND created_by=$me))`。
- **`RETURNING` で影響行を受け取り、0 行 = 競合/権限なし**として明示エラー(ToolError「他の操作と競合しました。再取得してください」)。「0 行を黙って無視」しない。
- **副作用のある write を、後で raise するトランザクション内に置かない**。確定させたい UPDATE はコミット経路に、例外はブロック外へ。
- 先行 read の Python チェックは **UX 用の早期エラー**としては残してよいが、**正しさの砦は必ず UPDATE 側**に二重で持つ。
- 挙動テスト(黒箱)はこの手の競合を捕まえにくい。**白箱レビュー(Codex 等)+ 楽観ロックの明示的な競合テスト**で補う。
