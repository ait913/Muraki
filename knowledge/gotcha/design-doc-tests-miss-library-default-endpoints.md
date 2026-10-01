---
title: 設計 doc ベースのテストは「ライブラリが既定で開けている endpoint」を見ない — 認証ライブラリ採用時はリリースゲートで静的レビューを必ず挟む
category: gotcha
project: global
tags: [reviewer, release-gate, codex, better-auth, auth, 2llm]
created: 2026-10-02
sources:
  - sessions/2026-10-01-37ab5196.md (wasawasa Phase 1 リリースゲート)
  - projects/wasawasa/.designs/20261002-phase1-core.md §6-7
---

## Context

wasawasa (Next.js 16 + better-auth) の Phase 1。Claude Reviewer は設計 doc §5〜§8 から 623 本 + E2E 69 本を生成して全緑 (GREEN)。リリース前ゲートで Codex に静的レビューをかけたら **NO-GO**、重大 3 件。全て実コードで裏が取れた。

## What

Claude Reviewer が見落とした 3 件に共通するのは「**設計 doc に書かれていない挙動**」だったこと:

1. **ライブラリの既定 endpoint**: better-auth は `/api/auth/get-access-token` `/refresh-token` `/account-info` `/list-accounts` を標準で開けており、ログイン済み Cookie で upstream (GitHub) の access token を JSON で返す。設計 doc §6-7「GitHub token はどの応答にも含めない」は書いてあったが、Reviewer は**自分たちが実装した endpoint** しかテストしない。ライブラリが勝手に生やした経路は列挙されない
2. **ロックの順序**: 設計は「環境行を FOR UPDATE」と書いていたが、FK 検査の `FOR KEY SHARE` との競合や、Project ロックを取らない経路との循環待ちは設計に無い。テストは「結果の不変条件」しか見られず、デッドロックは並列テストでも確率的にしか出ない
3. **分岐の抜け**: 障害猶予の分岐が `active=false` を見ない。設計 doc の表に「猶予は active=true のとき」と書いていなかったので、Reviewer はそのケースのテストを書けない

Codex の静的レビューはこれを 1 回目で 3 件、2 回目でデッドロック、3 回目で残存経路、4 回目で GO-WITH-FIXES と、4 往復で収束した (各 5〜9 分)。

## Why

設計 doc ベースのテスト生成は「設計に書いてあることが実装されているか」を検証する手法で、「設計に書いていないことが実装に**混入していないか**」は原理的に見られない。認証ライブラリ・ORM・フレームワークは既定で多くの経路を開けるので、採用時はこの盲点が必ず生まれる。

## How to apply

- **認証・認可ライブラリを採用した PJ のリリースゲートは Codex 静的レビューを省略しない** (Muraki CLAUDE.md の「デプロイに乗る変更は 2LLM 突合」はこのため)
- Architect は設計 doc の認証節に「**ライブラリが既定で開ける endpoint の一覧と、閉じるもの**」を書く (better-auth なら `disabledPaths`)。Reviewer はその一覧から 404 テストを生成できる
- 行ロックを設計に書くときは「どの tx が、どの順で、何をロックするか」の表を書き、FK 検査の `KEY SHARE` を考慮して親行は `FOR NO KEY UPDATE` にする ([[pattern/monotonic-number-ledger-allocate]] の Project 行ロックと同じ)
- Codex の NO-GO は Claude の GREEN と割れても **まず実コードで裏取り** (CLAUDE.md エスカレーション規約)。今回は 3/3 とも正しかった
- Codex 再レビューは「前回指摘 + 修正コミット SHA + 確認してほしい観点」を渡すと 5 分で返る。全体を毎回読ませない
