---
title: 共有DTOに非Optionalフィールドを足すと inline JSON を持つ既存テストが decode throw で落ちる
category: gotcha
project: atender
tags: [swift, codable, dto, test-fixtures, schema-migration]
created: 2026-06-26
sources:
  - Muraki/projects/atender/.designs/20260626-ios-resync-phase1.md §3.4
  - apps/ios/AtenderTests/AuthStoreTests.swift testBootstrapTokenValidSignsIn
---

## Context

iOS Phase iOS-1 再同期で `MeResponse.User` に `requiredAttendanceRate: Int` を**非Optional**で追加した (設計 §3.4、zod `z.number().int()` ミラー)。設計の「変更対象ファイル保全マップ」(§2.2/2.3) は Fixtures の `me.json` 更新は挙げたが、`Core/Auth/*` を「流用 (触らない)」に分類していた。

## What

`AuthStoreTests.testBootstrapTokenValidSignsIn` が落ちた。原因はこのテストが Fixtures を使わず **inline 文字列リテラルで `/api/me` レスポンス JSON を組んでいた**こと:

```swift
let meBody = #"{"user":{"id":"u1",...,"departmentId":"d1"},"setupStatus":{...}}"#
```

この JSON に新フィールド `requiredAttendanceRate` が無い。非Optional `Int` は欠落で `DecodingError` を throw → bootstrap の me-decode が失敗 → state が `signedIn` にならず `signedOut` のまま → assert 失敗。

実装は設計 §3.4 に忠実 (DTO は正しい)。落ちたのは**スキーマ変更に追従していない古い inline テストフィクスチャ**。

## Why

Fixtures の `*.json` は保全マップで「更新対象」として追える。だが **テストコード内に直書きされた JSON リテラル**は grep しないと見えず、保全マップから漏れる。非Optional フィールド追加は「その型の JSON を組む全箇所」に波及するが、inline JSON はその波及先として可視化されにくい。

## How to apply

- Architect: DTO に**非Optional**フィールドを足す設計を書くときは、保全マップに「Fixtures/*.json」だけでなく「**その型を inline JSON で組む既存テスト**」も洗い出す。`grep -rn '"user"\|MeResponse\|decode(.*Self)' AtenderTests/` で inline JSON テストを先に拾う。
- Developer: 非Optional フィールド追加時、`grep -rln '<隣接フィールド名>' AtenderTests/` で inline JSON を持つテストを探し、新フィールドを追記する。
- 代替: API が常に返す保証があっても、後方互換テストの安定のためフィールドを Optional + デフォルトにする選択肢もある (ただし zod が non-nullable なら設計上は非Optional が正)。トレードオフは「型の厳密さ vs 既存 inline テストの保守コスト」。
- Reviewer: DTO に非Optional 追加が入った再同期では、Fixtures を使う decode テストだけでなく **inline JSON を持つ無関係テスト (Auth 等) の退行**を必ず実行で確認する。
