---
title: 再入ガード (_running) と「最大 N 回の即時リトライ」を組み合わせると、背景で走っている同じ処理に N 回空振りして諦める
category: gotcha
tags: [flutter, async, retry, unawaited, design-review]
created: 2026-10-15
project: bloom
sources: [bloom 0.2.3 C U2a Reviewer (FootprintPlainMigration × HiddenCellsSync.save × uploadPending)]
---

## Context
平文足跡の移行は「`uploadPending()` を `dirtyCellDays()` が空になるまで最大 20 回」呼ぶ設計。`uploadPending()` は「`_running` なら return」の再入ガード付きで、移行の手順 1 で呼ぶ `HiddenCellsSync.save` が内部で `unawaited(uploadPending())` を起こす。

## What
dirty 行がある端末 (復元後の典型) では、手順 1 の背景送信がまだ走っている最中に手順 4 のループが始まり、20 回の呼び出しが全部 `_running` で即 return する (間に `await` が無いので数マイクロ秒で 20 回消費)。dirty が残ったまま「20 回で空にならない」と判定され、`migrated` を呼ばずに終わる。次の前景で背景送信が終わっているので完了する (自己回復するので気づきにくい)。

## Why
リトライの上限は「処理が失敗した回数」を数えるつもりだが、ガードによる空振りも 1 回に数えてしまう。

## How to apply
- 再入ガード付きの処理をループで呼ぶなら、(a) 実行中なら完了を待つ (Completer を返す)、(b) 空振りは回数に数えない、のどちらかにする。「戻ったら完了済み」を呼び出し側の契約にする。
- テスト: 「呼ぶ前に別経路で同じ処理が背景で走っている」状態 (dirty 行を 1 行置いてから移行を回す) を 1 本入れる。dirty 行ゼロの標本だけだと素通りする (U2a では P1 が緑で P1c / P2 だけが赤)。
