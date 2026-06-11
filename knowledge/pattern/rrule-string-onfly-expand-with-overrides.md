---
title: RRULE 文字列保存 + オンザフライ展開 + 編集 3 択 (single/future/all) の標準パターン
category: pattern
tags: [calendar, rrule, recurrence, prisma, rfc5545, edit-scope, override, rrule-npm]
created: 2026-05-27
project: global
sources:
  - RFC 5545 https://datatracker.ietf.org/doc/html/rfc5545
  - rrule npm (jakubroztocil/rrule) https://github.com/jakubroztocil/rrule
  - Google Calendar editing recurring events https://support.google.com/calendar/answer/37115
  - Mattermost Calendar plugin (onfly expansion 採用例) https://github.com/mattermost/mattermost-plugin-calendar
  - Cal.com schema.prisma (override テーブル参考) https://github.com/calcom/calcom
related_knowledge:
  - knowledge/pattern/calendar-week-pattern-meeting-expansion.md  # 週パターン Meeting の事前展開と対比
---

## Context

カレンダー / 予約 / 共有予定アプリで「繰り返し予定」を持ちたい場面。Google Cal / Apple Cal / Outlook と互換性のある RRULE (RFC 5545) を取り扱う必要がある時。

シリーズ単位の永続化 + 個別回の編集 (この回だけ / これ以降 / すべて) を扱う最小構成。

参考プロジェクト: Atender v7 (`projects/atender/.designs/20260527-v7-calendar-rrule-import.md`)、Mattermost Calendar Plugin、Outline doc reminders。

## What

### スキーマ (3 テーブル + enum 1 個)

```prisma
model Event {                       // = シリーズの親 1 行
  id              String  @id @default(cuid())
  title           String
  start           DateTime          // DTSTART (UTC)
  end             DateTime          // duration = end - start (全 occurrence で共通)
  recurrenceRule  String?           // "FREQ=WEEKLY;BYDAY=MO;UNTIL=..." (DTSTART 抜き)
  exDates         String?           // "20260615T090000Z,..." CSV
  rDates          String?           // 同上
  overrides       EventOverride[]
}

model EventOverride {               // = この回だけ上書き
  id            String   @id @default(cuid())
  seriesId      String
  series        Event    @relation(fields: [seriesId], references: [id], onDelete: Cascade)
  originalDate  DateTime              // 元 occurrence の DTSTART (RECURRENCE-ID 相当)
  isCancelled   Boolean  @default(false)
  newStart      DateTime?
  newEnd        DateTime?
  newTitle      String?
  @@unique([seriesId, originalDate])  // ★ 同じ回への override は 1 つだけ
}
```

### 保存方式: 生 RRULE 文字列

```ts
event.recurrenceRule = "FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261231T235959Z"
```

JSON 構造化や正規化テーブル化はしない。理由:
- Google Cal API と同形式 → 将来 OAuth 連携で変換不要
- `.ics` import 時にそのまま流し込める
- rrule npm の `RRule.fromString()` 一行
- DB クエリで RRULE 内の `FREQ` を絞る要件は実用上ない

### 展開: オンザフライ (request 時に展開)

`GET /week?weekStart=...` のような範囲 endpoint 内で展開:

```ts
import { rrulestr } from "rrule";

function expandWeek(event: Event, weekStart: Date, weekEnd: Date) {
  if (!event.recurrenceRule) return [event];  // 単発はそのまま
  const set = rrulestr(
    [
      `DTSTART:${toIcsDate(event.start)}`,
      `RRULE:${event.recurrenceRule}`,
      ...event.exDates.split(",").filter(Boolean).map(d => `EXDATE:${d}`),
      ...event.rDates.split(",").filter(Boolean).map(d => `RDATE:${d}`),
    ].join("\n"),
    { forceset: true },
  );
  const dates = set.between(weekStart, weekEnd, true);
  const durationMs = event.end.getTime() - event.start.getTime();
  return dates.map(d => ({
    seriesId: event.id,
    occurrenceDate: d,
    start: d,
    end: new Date(d.getTime() + durationMs),
    title: event.title,
  }));
}
```

事前展開 (シリーズ作成時に N 回分の `Occurrence` 行を INSERT) は採用しない:
- シリーズ編集時に大量 UPDATE/DELETE
- UNTIL 無しシリーズで埋める量が決められない
- 1 ルーム数十シリーズ規模なら onfly で 100ms 以内

### 編集 3 択 (single / future / all)

#### single = override 1 行追加

```ts
await prisma.eventOverride.upsert({
  where: { seriesId_originalDate: { seriesId, originalDate } },
  create: { seriesId, originalDate, newTitle, newStart, newEnd },
  update: { newTitle, newStart, newEnd },
});
```

cancel も同じ override で `isCancelled=true`。展開時にスキップ。

#### future = series 分割

```ts
// 1. 元シリーズの RRULE に UNTIL=originalDate-1ms を追加 (COUNT は除去)
const newOldRRule = appendUntil(series.recurrenceRule, originalDate - 1ms);
await prisma.event.update({ where: { id: series.id }, data: { recurrenceRule: newOldRRule } });

// 2. 新シリーズを originalDate から複製、UNTIL は元と無関係
await prisma.event.create({
  data: {
    ...patch,
    start: newStart,
    end: newEnd,
    recurrenceRule: stripUntil(series.recurrenceRule),
    exDates: null,  // 新シリーズは override / EXDATE をリセット
    rDates: null,
  },
});
```

#### all = series 直接 update

```ts
await prisma.event.update({
  where: { id: series.id },
  data: { title, start, end, recurrenceRule, ... },
});
```

### 削除 3 択も同じ構造

- single: override (isCancelled=true)
- future: 元 series に UNTIL=originalDate-1ms (新 series は作らない)
- all: series delete (CASCADE で override も削除)

### 上限値 (Hard limits)

| 値 | 上限 | 理由 |
|---|---|---|
| RRULE 文字列長 | 720 char | Google Cal 同等 |
| 展開範囲 | 1 年以下 | 無限ループ防止 |
| occurrence per series in range | 366 | サニティ |

### Identity (DTO 設計)

```ts
{
  id: seriesId,                      // 同じシリーズの全 occurrence で同じ
  seriesId: seriesId,
  occurrenceDate: ISO8601,           // 編集 3 択時にクライアントが送り返す
  overrideId: string | null,         // override がかかっている回のみ
  isRecurringOccurrence: boolean,
  recurrenceRule: string | null,
  start: ISO8601, end: ISO8601,
  title: string,
}
```

クライアントは `(seriesId, occurrenceDate)` の組を一意キーとして扱う。`id` を `${seriesId}:${occurrenceDate}` にする設計も可だが、既存 client が `id` を素朴に primary key として使っているなら seriesId 維持の方が破壊変更少ない。

## Why

- **オンザフライ展開は編集コストが O(1)**: scope=all でも 1 行 update。事前展開だと O(N) UPDATE
- **編集 3 択は業界標準**: Google Cal / Apple / Outlook 全部この UX。ユーザー学習コストゼロ
- **future = series 分割は元 RRULE を保ったまま新 series に複製**: 編集を「forward 適用」と「過去保護」両立。元 series の UNTIL 切断と新 series 作成は同一 transaction で行う
- **override テーブルは Cal.com 等の業界主流**: master series を残しつつ個別差分のみ持つ
- **生 RRULE 文字列**: import / export / 外部 API 連携 (.ics / Google) でロスレス
- **SQLite で String[] が使えない**: EXDATE / RDATE は CSV TEXT で十分 (RFC 上 1000 行超でも parse コストは無視できる)

## How to apply

1. **シリーズ親 1 行 + override 別テーブル + enum** を最初から分離 (後付けで合体 schema から剥がすのは破壊変更)
2. **RRULE 文字列保存、展開はオンザフライ**。事前展開は採用しない (Meeting 系の事前展開とは方針分離)
3. **EXDATE / RDATE は CSV TEXT** (SQLite 制約)。RFC 互換は parse 時に再構築
4. **編集 3 択 (single/future/all) を最初から body の `editScope` で受ける**。後付けで「editScope=all 想定の既存 endpoint に future を足す」と互換が崩れる
5. **future 分割時は新シリーズを fresh で作る** (override / EXDATE を引き継がない)。元シリーズの過去回は元 override 適用、新シリーズは新たに開始
6. **クライアントは `(seriesId, occurrenceDate)` をキー**にして CRUD ペイロードを組む。`occurrenceDate` は API レスポンスに必ず含める
7. **DTSTART は UTC 保存**、TZID 解釈はアプリ層 (dayjs / luxon) で。Floating time はユーザー TZ (例: Asia/Tokyo) として解釈
8. **RRULE 上限と range 上限は service 層で enforce**。`rrule.between(from, to, inc)` は構造的に無限ループしないが、`to-from` を制限しないとメモリ爆発の可能性
9. **rrule npm の WKST デフォルト `MO`** を仕様として受け入れる。Apple Cal の WKST 無視はクライアント表示の問題、サーバー側は固定で OK
10. **テストは fixture 駆動**: weekly / monthly BYDAY / BYMONTHDAY=-1 / EXDATE / RECURRENCE-ID の 5 種は最低 snapshot test を持つ

## 反例 / 限界

- **大量シリーズ (10000+)** はオンザフライで遅くなる。その規模なら事前展開 + 適切な index、または rrule-rs (Rust WASM) 検討
- **TZID 跨ぎ summer time** で「毎週 9:00」を厳密に保証したい場合、UTC 計算では DST で 1 時間ズレる。`rrule` の TZID option (Date 配列) + luxon で TZ 内計算が必要
- **AddPerson / RemovePerson** のような時間以外の semantics は RRULE では表現不可。別ドメインで扱う
- **PARTSTAT (出欠ステータス)** は RRULE と独立。本 pattern では「予定の枠」のみ扱い、出欠は Meeting / AttendanceRecord 系で分離する (Atender 設計参照)
