---
title: 出席率の分母から「一括休講日」を除外する標準パターン (Course × Date 中間テーブル)
category: pattern
tags: [attendance, course, suspension, denominator, prisma, schema-design]
created: 2026-05-28
project: global
sources:
  - Atender v9 設計 .designs/20260528-v9-timetree-rework.md
  - Atender 既存 attendanceStats.ts (RuleStrategy.REDUCE_DENOMINATOR)
---

## Context

出欠管理アプリで「学園祭振替で来週月曜は休講」のように**科目全体 × 特定日付**で休講を宣言する場面。個別 occurrence の `status=CANCELLED` で手動マークする方式だけだと:

- 同日複数コマある科目 (連続 2 コマ等) で漏れる
- 事前に「○月○日は休講」と一括宣言できない
- 集計時に分母から除外するロジックがバラける

## What

**`CourseSuspension { id, courseId, date, reason?, createdAt, updatedAt }` を中間テーブルで持ち、集計時に分母から除外する**。

### Prisma schema

```prisma
model CourseSuspension {
  id        String   @id @default(cuid())
  courseId  String
  course    Course   @relation(fields: [courseId], references: [id], onDelete: Cascade)
  date      DateTime          // 00:00:00 (アプリの TZ で正規化)
  reason    String?
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  @@unique([courseId, date])
  @@index([courseId])
  @@index([date])
}
```

### 集計ロジック (TypeScript)

```ts
const suspendedSet = new Set(course.suspensions.map((s) => toIsoDate(s.date)));

for (const occ of course.occurrences) {
  const occIso = toIsoDate(occ.date);

  // ★ CourseSuspension が AttendanceRecord より優先
  if (suspendedSet.has(occIso)) {
    counts.suspended += 1;
    denominatorReduction += 1;
    continue;
  }
  // ... 既存ロジック (AttendanceRecord の status 別 numerator 算出)
}

const denominator = Math.max(0, course.totalSessions - denominatorReduction);
```

### 個別 cancel との共存

| 概念 | 入力タイミング | 粒度 | 集計影響 |
|---|---|---|---|
| **CourseSuspension** | 事前に一括 | Course × Date | 該当日の全 occurrence を分母除外 |
| **AttendanceRecord.status = CANCELLED** | 事後に個別 | Occurrence | その occurrence のみ分母除外 |

**両方ある日付**は CourseSuspension が優先 (= 個別 record を見る前に continue で抜ける)。理由: 一括宣言 (= 公式) > 手動マーク (= 個人記録)。

### counts に別フィールドで分離

```ts
counts.cancelled  // = AttendanceRecord(CANCELLED) の件数のみ
counts.suspended  // = CourseSuspension に該当した occurrence の件数
```

UI で「休講 (個別)」「休講 (一括)」と分けて表示できる。

### API

```
GET    /api/courses/:courseId/suspensions             → list (date asc)
POST   /api/courses/:courseId/suspensions { date, reason? } → create (409 DUPLICATE 注意)
DELETE /api/courses/:courseId/suspensions/:id          → delete
```

認可: `Course.userTimetable.userId === currentUserId` の assert。

## Why

- **粒度が自然**: 「○月○日は休講」と科目に対して登録するのが学生の認識に合う
- **冪等**: `@@unique([courseId, date])` で重複登録不可
- **集計の単純化**: occurrence 1 件ごとに「suspended set に含まれるか」を `Set.has(iso)` で O(1) チェック
- **個別 cancel との共存**: 既存の `status=CANCELLED` 機能を壊さない (= 後方互換)
- **削除安全**: `Course.onDelete: Cascade` で suspension も一緒に消える

## How to apply

新規出欠アプリ / 既存アプリの拡張で:

- [ ] `<Entity>Suspension` の中間テーブルを作る (Entity = Course, Class, Session etc.)
- [ ] `@@unique([entityId, date])` を必ず付ける (冪等性確保)
- [ ] 日付は **アプリの TZ で 00:00:00 正規化** (`toIsoDate(jstStartOfDay(yyyyMmDd))`)
- [ ] 集計関数は `suspensionDates: Set<string>` を ist で前計算 → loop 内で O(1) check
- [ ] counts に `suspended` フィールドを追加 (`cancelled` と意味的に分離)
- [ ] API は CRUD 3 個 (list / create / delete)、update は不要 (= 消して作り直す)
- [ ] UI は科目編集 modal の中に section として置く (= 個別画面化しない、context 維持)

逆に**やらない**:

- `MeetingOccurrence.isSuspended: Boolean` で表現する (= 再生成で消える、一括宣言にならない)
- `AttendanceRecord` を勝手に CANCELLED で埋める (個別 mark の意図と混同)
- 過去日に対する登録を block する (= 後追いで「先週は休講だった」とマークできる柔軟性が要る)
- 「全科目 × 特定日」(= 学校全体休講) の一括登録 (Atender MVP では不要、複数 course 同時操作は UI で済ます)

## 反例 / 限界

- **同日に course が複数あって一部だけ休講**のケースは Course 単位で suspension を持つこのモデルでは表現できない (= 全部か無しか)。粒度を上げたければ Meeting 単位の suspension を別 schema で持つ必要があるが、MVP では Course 単位で十分
- **学校全体休講**: 全 course 行をループして bulk insert すれば実現可。専用 API は MVP 不要
- **将来 LMS 連携**: 学校配信の「公式休講通知」を取り込む場合、`source: "SYSTEM" | "MANUAL"` の enum を足す拡張パスを残しておく
