---
title: 週パターン (曜日+時限) → 絶対日付 occurrence 展開を Backend に寄せる pattern
category: pattern
tags: [calendar, schema, week-pattern, occurrence, atender, prisma]
created: 2026-05-27
project: global
sources:
  - Atender Phase 1 MVP schema (Meeting / MeetingOccurrence)
  - Atender v3 設計 (Rooms / Friends)
  - Atender v6 設計 (RoomCalendar / RoomTimetable)
---

## Context

時間割 / 繰り返し予定 / シフト等で「毎週月曜の 1 限」のような週パターンと、出欠記録のような「特定日の単位」を両立させる schema 設計。展開ロジックを Backend / Frontend のどちらに置くかの判断基準。

## What

### Schema 分離

```prisma
model Meeting {
  id              String @id
  userTimetableId String
  courseId        String
  dayOfWeek       Int        // 0-6 or 1-7
  startPeriodIndex Int
  periodCount     Int        // 連続コマ数
  // = 週パターン (週ごとに繰り返す)
}

model MeetingOccurrence {
  id            String @id
  meetingId     String     // FK Meeting
  courseId      String     // 非正規化 (検索用)
  date          DateTime   // 絶対日付 (00:00:00 JST)
  startMinute   Int        // 当日絶対時刻 (snapshot)
  endMinute     Int
  // = 1 つの絶対日付 × 1 つの period
}
```

### Backend で展開する

`GET /api/rooms/:id/week?weekStart=YYYY-MM-DD` のような API で、`weekStart` から `weekEnd` の範囲で `MeetingOccurrence` を返す。

理由:
- Frontend が毎回「Meeting × 週」のクロス product を計算するのは重複作業
- Backend で展開済みなら、出欠記録 (`AttendanceRecord`) との JOIN が直接 occurrence で可能
- 学期境界 / 祝日休講 / DaySlot 時刻変更 などのドメインロジックを 1 か所に集約できる

### Frontend は date filter のみ

```ts
// 月表示: 5-6 週分を useQueries で並列 fetch
const weekStarts = ["2026-04-27", "2026-05-04", ..., "2026-06-01"];
const weeks = useQueries({ queries: weekStarts.map(ws => ({...}))});

// merge: 全週の occurrence を flatten + dedup
const events = weeks.flatMap(w => w.data?.meetings ?? []);
const byDate = new Map(); for (const e of events) byDate.set(e.date, [...(byDate.get(e.date) ?? []), e]);
```

### snapshot 列 (`startMinute` / `endMinute`)

`MeetingOccurrence` に `startMinute` / `endMinute` を**非正規化で持つ**。DaySlot 変更耐性のため:
- ユーザーが今期途中で DaySlot の時刻を変更 (例: 1 限を 9:00→9:15) しても、過去 occurrence は当時の時刻で記録されたまま
- 出欠記録の遡及修正が起きない (= legal trail)

## Why

- **責務分離が綺麗**: Backend = 「いつ」、Frontend = 「どう描画」
- **キャッシュが効く**: TanStack Query で `[/rooms/:id/week, weekStart]` キャッシュ。週単位粒度なら 1 月 view = 5-6 query で済む
- **テストが書きやすい**: occurrence 展開 (Backend) は pure SQL で確認、Frontend は decode → render の 1 段だけ
- **複数メンバー対応が自然**: 1 ルームに N メンバー → Backend で N 人の Meeting を全部展開してまとめて返す。Frontend は member ごとに filter するだけ

## How to apply

1. **schema は week-pattern と occurrence を必ず分離**。occurrence 直書きで「毎週繰り返し」を表現しない (= 学期分のレコードを毎回 INSERT する設計はパフォーマンス・整合性で破綻)
2. **occurrence 展開は週単位の endpoint** で API 化。クライアント側で `dayOfWeek + period → date + minute` 変換を書かない
3. **`useQueries` で複数週並列 fetch**、月表示 / 範囲指定はクライアントで集約
4. **`startMinute` / `endMinute` は occurrence に snapshot**、上流 (DaySlot / Course) の変更に耐える
5. RoomEvent (絶対日付) と Meeting (週パターン) は同じ DTO 内で別フィールドとして併存させる (= `meetings[]` と `roomEvents[]`)、フロントで `kind` 識別

## 反例 / 限界

- occurrence を週単位で fetch すると、年単位の検索 (例: 出席率の月別集計) では別 endpoint が必要 (= `/api/stats/monthly`)。1 つの API で全てを賄おうとしない
- 毎週同曜日固定の RoomEvent (= 週パターン RoomEvent) は MVP では扱わない。導入する場合 `RoomEvent` を `RoomEventPattern` + `RoomEventOccurrence` に分離する追加コスト
- カレンダー drag&drop で「来週に移動」操作を許すなら、Meeting (週パターン) を編集するか、occurrence override テーブルを足す。occurrence 直接編集は Meeting との整合性が崩れる
