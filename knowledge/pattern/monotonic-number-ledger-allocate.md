---
title: 単調増加の番号払い出しは「カウンタ + 台帳 (予約/使用/破棄)」で持つ (build 番号・伝票番号)
category: pattern
project: global
tags: [numbering, build-number, counter, ledger, idempotency, postgres, row-lock, allocate]
created: 2026-10-02
sources:
  - Muraki/projects/wasawasa/.designs/20261002-phase1-core.md §4-2 build_numbers / §5-7
---

## Context

iOS の CFBundleVersion のように「プロジェクト内で単調増加・再利用禁止・画面から手で直せる・配布スクリプトが先に番号だけ取り後で成果物を登録する」番号を払い出す場面 (wasawasa の client build 番号)。伝票番号・請求書番号など「欠番は許すが重複と再利用は許さない」系に共通。

## What

- **カウンタ** (`projects.next_build_number`) と **台帳** (`build_numbers(project_id, number) PK, state reserved|used|void, build_id, idempotency_key`) の 2 つで持つ。成果物の表 (builds) の番号列は台帳を引く側
- 払い出し: `SELECT … FROM projects WHERE id=$1 FOR UPDATE` → `n = next`、**台帳に `n` がある間 `n++`** → `INSERT 台帳 (reserved)` → `next = n + 1`。Project 行ロック 1 つで払い出し・カウンタ変更・手動登録が直列化される
- 手動登録 (過去分の取り込み・番号指定): 台帳に無ければ `used` で挿入し、`n ≥ next` なら `next = n + 1`。`reserved` なら `used` へ。`used`/`void` は 409
- 成果物を削除しても台帳行は残す (`build_id` が NULL になるだけ) → **再利用しないが台帳 1 か所で保証**される
- カウンタを使用済み最大以下へ下げる操作は確認付きで許し、払い出し側が台帳を見て使用済みを飛ばす (下げても重複は起きない)
- 冪等: 払い出し要求に任意の `idempotency_key` を持たせ、`(project_id, idempotency_key)` UNIQUE。スクリプトのリトライで番号が 2 つ消費されない
- 「予約されたまま使われなかった番号」は台帳の `reserved` として画面に出し、破棄 (`void`) できる

## Why

- 成果物の行に「予約中」状態を持たせる案は、削除で使用履歴が消えて「再利用しない」を保証できず、current 選定などの集計に予約行の除外が要る
- DB シーケンスは手動変更・使用済みのスキップ・冪等キーが表現できない。払い出し頻度が低い (人の操作・配布 1 回 1 番号) なら行ロックで十分で、アドバイザリロックや SERIALIZABLE は要らない
- 「カウンタを下げる」要望 (誤入力の修正) と「重複させない」不変条件が両立するのは、真実を台帳に置き、カウンタを「次の候補」に格下げしたから

## How to apply

- 設計 doc に「払い出しアルゴリズム (ロック対象・スキップ規則・冪等キー)」「台帳の状態遷移」「削除時に台帳がどうなるか」を書く。挙動仕様に「N 並列で払い出して重複なし・連番」「下げたカウンタからの払い出しが使用済みを飛ばす」「削除済み番号の再登録が 409」を入れる
- 冪等キーの UNIQUE 違反 (同キーの並行要求) はトランザクションを捨てて先頭からやり直す (最大数回)
