---
title: BEFORE トリガーで取る advisory lock は、別 tx の「ロック → FK 付き INSERT」と逆順になりデッドロックする
category: gotcha
tags: [postgres, advisory-lock, trigger, deadlock, bloom, testing]
created: 2026-10-15
project: bloom
sources: [bloom 0.2.3 C U1 Reviewer (feature/touri-023-e2e)]
---

## Context
bloom 0.2.3 の E2E 鍵 (migration 0019) は、`memberships` の INSERT/DELETE に BEFORE FOR EACH ROW トリガーを付け、`pg_advisory_xact_lock(hashtext('gkey:'||group_id))` を取って「脱退と epoch 作成を直列化」する設計だった。

## What
- 設計 doc の交差の書き下し (脱退が先 / epoch 作成が先 の 2 通り) は正しく、直列化自体は機能した。しかし**同時に撃つと脱退 (`DELETE /v1/groups/{gid}/membership`) と epoch 作成 (`POST …/keys/epochs`) が約 1 秒後に deadlock detected で片方 500** になった (15 回中 14〜15 回)。join × epoch、reset × epoch、脱退 × reset、退会 × 退会は無事。
- PG ログ: 脱退側は `DELETE FROM memberships` が advisory lock 待ち、epoch 側は `INSERT INTO group_key_wraps` が脱退 tx の保持する tx-lock 待ち (= 脱退 tx が advisory lock より前の文で別の行ロックを取っている)。ロック順序が「脱退: 行ロック → advisory」「epoch: advisory → FK 先の行」で逆。
- BEFORE トリガーのロックを外すとデッドロックは消えたが、直列化テスト (排他ロックを外から握って脱退が待つか) が赤になる。つまりトリガーのロックが衝突の当事者。

## Why
advisory lock は「全経路が最初の文で取る」前提で初めてデッドロックしない。トリガーで取ると、呼び出し元 tx が**その前に**取った行ロック (SELECT FOR UPDATE、先行 DELETE、FK の KEY SHARE) が先行するので、別経路 (lock → INSERT) と順序が逆になる。

## How to apply
- advisory lock で直列化する設計では、**全書き込み経路の tx の第 1 文でロックを取る** (トリガー任せにしない)。既存の `LeaveGroup` のように先に行ロックを取る経路があるなら、そこにも先頭で同じ advisory lock を足す。
- Reviewer: 並行のデッドロックは「2 経路を goroutine で同時に撃つ × 15 回」の総当たり表 (対ごとの 5xx 率) にすると、衝突する対が一発で絞れる。決定的な再現は、テストから同じキーの advisory lock を握って片方を待たせ、中で相手が必要とする行に INSERT する。PG のログ (`docker logs <pg> | grep -A6 'deadlock detected'`) に当事者の文が出る。
- 500 まで 1 秒かかる (deadlock_timeout) ので、待ち時間の長いリクエスト = デッドロックの兆候としても見られる。
