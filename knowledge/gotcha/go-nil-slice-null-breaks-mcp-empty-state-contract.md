---
title: Go nil slice が JSON null になり MCP 空状態契約 (空配列) を破る
category: gotcha
project: dandan-app
tags: [go, mcp, go-sdk, json, empty-state, structured-output]
created: 2026-07-05
sources:
  - dandan-app Slice2 Reviewer round (sessions/2026-07-05)
  - .designs/20260705-stateful-multitenant.md §7.3 空状態契約
---

## Context

MCP ツールの typed struct 出力 (go-sdk `AddTool[In, Out]`) で「空状態はエラーでなく空コレクションで返す」契約を設計docに書いた。実装は Out struct の slice フィールドを未初期化 (nil) のまま返した。

## What

Go の nil slice は `json.Marshal` で `null` になる。`[]T{}` だけが `[]` になる。dandan-app Slice2 では 21 ツール中、空になり得る全 slice フィールド (plans / insights / relations / applied / errors / created / issues / github_loads / not_ready_reasons / work_items ...) が wire 上 `null` で観測された。テスト 9 箇所で一斉に fail する系統的パターン。

## Why

設計docが「空配列で返る (null やエラーにしない)」を wire 契約として明記しても、Go では各ハンドラ / store 層が slice を明示初期化しない限り自然に破れる。scan ループで `var xs []T` → 0 行なら nil のまま、が典型経路。

## How to apply

- Developer: 設計に空状態契約がある Out struct は、コンストラクト時に全 slice を `make([]T, 0)` or リテラル `[]T{}` で初期化する。store 層の戻り値でなくツール出力組み立て側で保証するのが漏れにくい。
- Reviewer: 空状態契約のテストは「フィールド存在 + null でない + len==0」の 3 点で assert する (len==0 だけだと null を見逃す。Go で decode すると null も len 0 になるため、`map[string]any` の値が nil かを見る)。
- 検出したら Fatalf でなく Errorf + 空 slice 返しでテスト続行にすると、null 契約違反の裏の挙動まで一括で検証できる。
