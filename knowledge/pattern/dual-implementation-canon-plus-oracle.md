---
title: 同じ規則が 2 実装あるとき「正典 + テストのオラクル」に役割を割る
category: pattern
project: omatase
tags: [design-doc, drift, sql, testing, integration-test, single-source-of-truth]
created: 2026-07-30
sources:
  - Muraki/projects/omatase/.designs/20260730-rebuild-screens.md (§7.4 期限規則の正典 / §13 #H1-#H3b / §14)
  - Muraki/knowledge/gotcha/fake-store-tests-miss-db-constraint-drift.md
model-era: opus-4.8
---

## Context

同じ計算規則が 2 箇所に書かれてしまう状況。omatase の自動アーカイブでは
「最終プランの終わり + 猶予」が **Go の関数 (`archive.Deadline`)** と
**1 文の集合 UPDATE (SQL)** の 2 実装になった。本番経路が通るのは SQL だけで、
Go 関数は**どこからも呼ばれていない**のに単体テストが緑になっていた。

## What

2 実装を 1 実装に潰せないことがある (集合更新は SQL 1 文が最適で、Go に寄せると N+1 になる)。
その場合の着地は「片方を消す」でも「両方本番で使う」でもなく、**役割を明示的に割る**:

- **正典 = 本番経路が通る実装** (ここでは SQL)。書かれる値を決めるのはこちら
- **もう一方 = 実行可能な仕様 + integration テストのオラクル**。
  本番から呼ばず、**「SQL が書いた値 == Go 関数の返り値」を assert する**ためだけに使う

これで 2 実装の drift が**テストで検出可能**になる (どちらかを直し忘れると赤くなる)。

さらに**層の切り分け**が必要になる: `Deadline(lastEnd, createdAt, grace)` は
「解決済みの最終時刻」を受ける契約なので、`end_time ?? start_time` の解決は SQL の
`coalesce` の責務。**この項目は単体テストでは表現できない**ので、挙動仕様の #番号ごとに
「どの層で検証するか」を書き分ける (書かないと Reviewer が単体に置いて偽の緑になる)。

## Why

- 呼ばれない関数の単体テストは**本番経路を 1 バイトも通らない**。緑が「正しさ」を意味しない
- かといって消すと、規則が SQL の中の式にしか無くなり、**読める仕様が消える**
- 「オラクル」として使えば、テストが通る限り 2 実装は同値であり続ける (証明ではないが検出はできる)
- 定数 (猶予日数) は片側に 1 箇所だけ置き、もう片方は引数で受ける = **定義の重複はゼロにできる**

## How to apply

- 設計 doc に **「正典はどちらか」を 1 行で書く**。書かないと Developer が Go 側を直して SQL を忘れる
- integration テストに **「本番経路が書いた値 == オラクルの返り値」** の assert を必ず 1 本置く
- 挙動仕様の各項目に **検証層 (単体 / integration)** を明記する。
  特に「片方の関数のシグネチャでは表現できない項目」は単体から外す
