---
title: 「今日」をサーバと別の暦で決めると、毎日 N 時間だけ壊れる
category: gotcha
tags: [timezone, date, api-contract, ios, swift, dayjs, calendar]
created: 2026-07-17
project: global
sources:
  - atender iOS UI 刷新の設計 (2026-07-17) — Architect がシミュレータで実測
  - projects/atender/.designs/20260717-ios-ui-revamp.md (F3/F4)
---

## Context

atender の API は `apps/api/src/lib/tz.ts` で `APP_TZ = "Asia/Tokyo"` を固定し、
`GET /api/today` は **JST の今日**を返す。

iOS 側は日付文字列の代数 (`parse` / `addDays` / `mondayOf` / `monthFirst`) を持つ `CalendarRange` に
**UTC 固定のカレンダー**を持たせていた。そこは正しい設計 — `"2026-07-17"` を UTC 正午として扱えば
足し算しても文字列に戻せて round-trip が閉じる。

**問題は、その UTC モジュールに `todayString()` (= 今が何日か) を生やしたこと。**

## What

**`yyyyMMdd(Date())` を UTC カレンダーで評価すると、JST の 00:00〜08:59 の 9 時間、サーバと違う日付を返す。**

実測 (シミュレータ):

| 実時刻 (JST) | client (UTC 暦) | server (JST) | 一致 |
|---|---|---|---|
| 2026-07-17 00:30 | **2026-07-16** | 2026-07-17 | ✗ |
| 2026-07-17 08:00 | **2026-07-16** | 2026-07-17 | ✗ |
| 2026-07-17 08:59 | **2026-07-16** | 2026-07-17 | ✗ |
| 2026-07-17 09:00 | 2026-07-17 | 2026-07-17 | ○ |
| 2026-07-17 23:00 | 2026-07-17 | 2026-07-17 | ○ |

同じ原因で「0 時からの経過分」も壊れる: **JST 08:00 → UTC 暦だと `1380` 分** (正しくは `480`。1 限 = 540)。

**実害の例** (atender で発見):
- カレンダーの anchor が朝 9 時前は前日 → 「今日」の強調が 1 日ズレる
- `mondayOf(todayString())` で週を取る画面が、**月曜の 9 時前に「先週」を読む** (Sunday → 前週の月曜に丸まる)
- 9 ヶ月間、誰も気付いていなかった

## Why

- **UTC ずれ 9 時間 = 1 日の 37.5%** だが、**開発者が触る時間帯 (日中) では絶対に再現しない**。
  朝の通学時間帯だけ壊れるので、バグ報告も上がらない
- テストが `Date()` の既定引数に頼っていると、**CI が回る時刻によって通ったり落ちたりする**ため、
  結局「時刻に依存するテスト」は書かれず、この経路は永久に無検証になる
- 「日付文字列の代数」と「今が何日か」は**別の責務**なのに、どちらも `Date` と `Calendar` を使うので
  同じモジュールに置きたくなる。置いた瞬間に暦の選択が衝突する
  (代数は UTC で閉じるのが正しい / 「今日」はサーバの TZ で決めるのが正しい)

## How to apply

- **「今日」はサーバの TZ で決める。デバイスのロケール (`Calendar.current`) でもなく UTC でもない。**
  サーバが `APP_TZ` を固定して「今日」を決めている以上、クライアントが別の暦で決めれば必ず食い違う。
  海外対応が必要になったら API の `APP_TZ` から一緒に直す話であって、クライアントが先に分岐する話ではない
- **「日付文字列の代数」と「時計」をモジュールごと分ける**:

  ```swift
  enum CalendarRange { /* UTC 暦。parse / addDays / mondayOf … round-trip が閉じる */ }
  enum SchoolClock   { /* Asia/Tokyo 固定。nowMinute / todayString / displayDay */ }
  ```

  `CalendarRange.todayString()` のような**混在した 1 関数**が事故の入口。代数モジュールに「今」を置かない
- **時計に依存する関数は必ず `Date` を引数で受ける** (既定引数 `Date()` は本番用)。
  テストは既定引数を使わない — 使うと「テストを走らせた時刻」に依存して深夜に落ちる
- **テストは境界の両側を刺す**。「9 時間ズレる」は 1 点測っても見えない:

  ```swift
  // JST 08:00 と 09:00 の 2 点で挟むと、UTC 実装なら必ず片方が落ちる
  XCTAssertEqual(SchoolClock.todayString(jst("2026-07-17 08:00")), "2026-07-17")   // ← UTC 実装だと "2026-07-16"
  XCTAssertEqual(SchoolClock.todayString(jst("2026-07-17 09:00")), "2026-07-17")
  ```

- **同型の匂い**: `new Date().toISOString().slice(0,10)` (JS)、`date.today()` (Python、サーバ TZ が UTC の場合)、
  `LocalDate.now()` (Java、既定 TZ 依存) も全部同じ罠。**「今日」を暦の指定なしに取る API は全部疑う**
