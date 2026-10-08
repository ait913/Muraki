---
title: 「後片付け」の提案は event 時に記録せず現在の状態から毎回導出する
category: pattern
tags: [suggestion, derived-state, idempotent, no-migration, mcp, ux, wasawasa]
created: 2026-10-09
project: global
sources:
  - Muraki/projects/wasawasa/.designs/20261009-release-branch-suggestion.md
  - Muraki/projects/wasawasa/.designs/20261003-deploy-mcp-slack-responsive.md (§5-1 / §7-6)
---

## Context

wasawasa で「prod にデプロイした後、リリースの `git_branch` を master に切り替えて」と促したい。素直な案は完了 event (`deploy.finished`) の時にモーダル / toast で聞く・run に「提案済み」列を足す、だった。本番デプロイは非同期でモーダルは受付で閉じ、toast は 2.2 秒で消え、別の人がデプロイしていれば誰も見ない。

## What

提案を **event の副作用でなく、現在の状態 (既存列) から毎回計算する純関数** にした。発火条件は「固定ブランチの環境の `server_release_id = release.id` ∧ `release.git_branch ≠ deploy_branch` ∧ `git_branch ≠ NULL`」の 4 辺だけ。載せる先は既存の読み取り DTO (`ReleaseDTO.suggestions`) と、完了を知る経路の包み (MCP `deploy_status` / `deploy` の戻り)。承諾は既存の編集 API (`PATCH { git_branch }`)、却下の記録は持たない。新列・migration・新 Event kind・新エンドポイントは 0。

## Why

- 「誰がやっても後から気付ける」は event 駆動では満たせない (見ていなかった人には届かない)。状態駆動なら開いた瞬間に出る
- 承諾すると条件の 1 辺が偽になって自然に消える = 「消す」コードが要らない。同じリリースを再デプロイしても状態だけで出る (run の `merge_ack` 列を見ない)
- 却下を記録すると「状態は同じなのに人によって出たり出なかったり」になり、別の人が気付けない。放置 = 現状維持で足りる
- 提案の要素に `how` (どのツール / API で直すか 1 文) と `note` (副作用の注記。例「dev にも載っている。以後 dev のデプロイも master になる」) を持たせると、AI クライアントは description の 1 文「人に確かめてから `release_update`」だけで扱える

## How to apply

- 「○○した後に△△を直して」系の要望は、まず「△△が直っていない状態」を既存列だけで言えるか書き出す。言えれば event 時の記録は不要で、純関数 1 本 + 既存 DTO への配列追加で済む
- 条件の各辺が偽の時に出ないこと・承諾後に消えること・NULL (意図的な「無し」) を対象外にすること、を挙動仕様の最小セットにする
- 複数の対象 (環境) が当たるなら対象ごとに 1 要素にして、片方の承諾でもう片方が残る/消えるを仕様に書く
- 同期の DTO ビルダー (`deployRunDTO` のような行 → DTO の純関数) に DB 読み取りを混ぜたくなったら、poll される経路かを先に見る。poll 経路の DTO は変えず、包み (MCP ツール / RSC loader) で足す
