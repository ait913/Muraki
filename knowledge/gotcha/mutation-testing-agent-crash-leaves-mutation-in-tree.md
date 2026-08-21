---
title: 変異注入中に agent が落ちると、変異が実装に残ったまま次のフェーズへ流れる
category: gotcha
project: global
tags: [testing, mutation-testing, subagent, reviewer, git, worktree]
created: 2026-07-30
sources:
  [
    "omatase 画面編 工程3 (2026-07-30) — Reviewer A が API エラーで停止し packages/shared/src/plan.ts に変異が残留",
  ]
model-era: opus-4.8
---

## Context

Reviewer に「負のコントロール (変異注入)」をやらせる運用をしている。テストが本当に効いているかを確かめるため、実装を意図的に壊してテストが赤くなるかを見る手法で、これ自体は正しい。

omatase の画面編で、Reviewer A に `packages/shared` の変異注入を依頼した。Reviewer は「実装ファイルを `cp` / `git checkout` で必ず元に戻す」手順を持っていた。

## What

**Reviewer が変異を入れた直後に API エラー (`Connection closed mid-response`) で停止し、変異が実装に残った。**

残っていたのは `applyFeatureResponse` の先頭への 1 行:

```ts
export function applyFeatureResponse(plans, data) {
  return plans;        // ← 変異が残留
  const plan = plans[data.plan_id];
  ...
}
```

これは「メンバーの応答 (持ち物チェック / TODO 完了) の差分適用を全部無効にする」変異で、**症状は「リアルタイム更新が黙って死ぬ」**。ビルドは通り、lint も通り、その関数のテストだけが赤くなる。

★ **危ないのは「戻し忘れ」ではなく「戻す前に死ぬ」こと。** agent 自身が復帰できないので、後片付けのコードは実行されない。**agent 側の作法をどれだけ丁寧にしても防げない** (finally 相当が走らない)。

## Why

- 変異注入は「壊す → 確認 → 戻す」の 3 手順で、**壊れている時間窓が必ず存在する**
- subagent は API エラー / タイムアウト / kill で任意の時点に停止しうる。その窓に当たれば変異が残る
- 変異は 1 行の早期 return のような**構文的に完全に正しいコード**なので、型チェックも lint も通る
- 並列レーンが同じ worktree を共有していると、**別レーンの agent が変異入りの実装を前提に次のフェーズを書き始める**余地がある (今回は Leader が先に気付いて止まった)

## How to apply

**Leader (呼び出し側) の責務にする。agent の作法に委ねない。**

- ★ **subagent が異常終了したら、報告を読む前に `git status` と `git diff` を見る。** 「失敗した = 何もしていない」ではない
- 変異注入を依頼する前に **worktree を commit 済み (clean) にしておく**。そうすれば残留変異は `git diff` に必ず現れ、`git checkout -- <path>` で確実に戻せる。未コミットの実装に変異を混ぜると**変異と本物の実装差分が区別できなくなる**
- 復旧は**対象ファイルだけ**に `git checkout -- <path>` を打つ。`git checkout .` や `git restore .` は**並列レーンの未コミット作業を消す** (`gotcha/git-checkout-restore-destroys-uncommitted-work.md`)
- 戻したあと**テストを実際に回して緑を確認する**。「戻したつもり」で先に進まない
- 恒久策として、変異注入は**別 worktree (`git worktree add --detach`) の使い捨てコピー**で回すのが安全。本番の作業 worktree を壊さないので、agent が死んでも影響が出ない

## 関連

- [[git-checkout-restore-destroys-uncommitted-work]] — 復旧手段の側の罠
- [[deleted-tests-make-tagged-test-job-vacuously-green]] — 「テストが効いていない」を検出したい動機の側
