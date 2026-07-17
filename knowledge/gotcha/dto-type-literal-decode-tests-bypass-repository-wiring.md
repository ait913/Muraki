---
title: DTO 型直書きの decode テストは repository の配線を検証しない (層は全部正しいのに画面が壊れる)
category: gotcha
project: atender
tags: [swift, codable, testing, repository, api-contract, test-blind-spot]
created: 2026-07-17
sources:
  - apps/ios/AtenderTests/DTODecodingTests.swift:326 (旧: 型直書き)
  - apps/ios/AtenderTests/RoomWeekContractTests.swift (Reviewer 新規: 配線を通す)
  - fix/room-week-contract (eb96e8a)
---

## Context

atender iOS で「ルーム詳細画面が丸ごとエラー表示」になるバグ。原因は `RoomRepository.roomWeek()` が
`GET /api/rooms/:id/week` のレスポンスを `{week: ...}` という **存在しないラッパー** (`RoomWeekResponse`)
として decode しようとしていたこと。実 API はラッパー無しで week を**むき出し**に返す。

`/api/rooms` → `{rooms}` / `/api/rooms/:id` → `{room}` / `/api/rooms/:id/members` → `{members}` は包むため、
**week だけが例外**。この非対称が「揃えてしまう」実装ミスを誘発する。

## What

**このバグは iOS テスト 174 GREEN の下で生き延びていた。**

既存の decode テストがこう書かれていたため:

```swift
// DTODecodingTests.swift:326 — 型を直書きしている
let week = try makeDecoder().decode(RoomWeekDto.self, from: try loadFixture("roomWeek"))
```

fixture (`roomWeek.json`) は正しいラッパー無し形状。`RoomWeekDto` も正しい。`APIClient` も正しい。
**この test は「fixture が RoomWeekDto として読めるか」しか見ておらず、repository が
`client.send(_, as:)` に実際に渡す型を一度も実行していない。**

- DTO 層: 正しい ✅
- APIClient 層: 正しい ✅
- **両者を繋ぐ配線 (repository の `as:` 指定): 無テスト ❌** ← ここだけが壊れていた

つまり **DTO の decode テストをいくら増やしてもこのクラスのバグは永久に捕まらない**。

## Why

型直書きの decode テストは、テストの著者が「正しい型」を手で書いてしまうので、
**プロダクションコードが選ぶ型と一致しているかを検証する機会が原理的に存在しない**。
テストと実装が同じ答えを独立に持っているだけで、両者が突き合わされていない。

カバレッジ計測でも DTO と APIClient は「テスト済み」に見えるため、盲点が可視化されない。

## How to apply

- **Reviewer**: API レスポンスを decode する層のテストは、**repository (実際に `as:` を渡す経路) を通す**。
  URLProtocol スタブ + 実 `APIClient` + 実 repository を組み、**実 API から採取した生レスポンス**を食わせる:

  ```swift
  let repo = RoomRepository(client: try makeClient(), cache: QueryClient())
  respond(json: try liveFixture("roomWeekLive"))   // 実 API 採取。手打ちしない
  let week = try await repo.roomWeek(id: "room_1", weekStart: "2026-07-13", force: true)
  XCTAssertFalse(week.members.isEmpty)
  ```

- **負のコントロールを必ず対に置く**: 「ラッパー付きは decode 失敗すべき」テストを書く。
  これが無いと契約の**向き**が固定されず、実装がどちらでも緑になる余地が残る。
  (実際、修正前コードに戻すとこのテストが `members=2` で decode 成功して落ち、バグを直接可視化できた)

- **Architect**: エンドポイントのラッパー有無が**不揃い**な API では、設計docに
  「どれが包み、どれが包まないか」の一覧を書く。`week` のような例外は明示しないと実装が揃えにくる。

- **スタブ JSON を手打ちしない**: 手打ちは必須キー漏れで偽 fail を生む
  (本件でも Reviewer が `room` の `myRole`/`showMemberTimetables`/`upcomingEvent` を落として 1 ラウンド浪費)。
  稼働中の実 API から `curl` で採取して fixture 化する。関連: `gotcha/non-optional-dto-field-breaks-inline-json-tests.md`
