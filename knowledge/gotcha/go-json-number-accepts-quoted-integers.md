---
title: Go の json.Number / UseNumber は "5" (引用符付き) を整数として受ける
category: gotcha
tags: [go, json, validation, reviewer]
created: 2026-10-31
project: wacha
sources: [server/test/review/main_mw_test.go (TestMW16b), server/review_unit/core_test.go]
---

## Context

wacha server (Go) の内部 API / 入室 JWT / ゲームモジュールの action は「整数」を設計で規定していた。
ResultBody の検証は 1.5 や -1 や 1e2 は弾くのに、`{"score":"5"}` `{"winner":"0"}` `{"slot":"0"}` は通った。

## What

整数の判定を `json.Number` (または `UseNumber` した interface{}) で行うと、`encoding/json` は
**JSON 文字列 `"5"` を数値として受理する** (json.Number は引用符付きの数値リテラルを許す)。
`float64` / `int` に直接 Unmarshal した場合は型エラーになるので、実装が `json.Number` を使っている所だけで起きる。
検出は 1 本の負テストで足りる: 各整数フィールドに文字列 `"5"` を入れて 4xx / 拒否になることを見る。

## Why

json.Number の仕様 (string 型で、数値形式の文字列なら Unmarshal を許す)。設計 doc の「整数」は JSON の number 型を意味する。

## How to apply

- 整数フィールドを持つ wire (ResultBody / JWT claims / action) の検証テストには、境界値 (-1, 上限+1, 1.5, 1e2) と並べて**文字列 `"5"`** を必ず入れる。
- 実装側は `json.Number` を受けたら元のトークンが文字列だったか (`dec.Token()` で型確認) を見るか、`json.RawMessage` の先頭バイトが `"` でないことを検査する。
