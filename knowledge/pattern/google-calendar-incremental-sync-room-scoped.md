---
title: Google Calendar 連携を Connection (user) × Sync (room × calendar) の 2 段 schema で組むパターン
category: pattern
project: global
tags: [google-calendar, oauth, sync-token, polling, prisma, sqlite, room-scoped, dedup, syncing-mutex]
created: 2026-05-28
sources:
  - https://developers.google.com/calendar/api/guides/sync
  - https://developers.google.com/calendar/api/v3/reference/events/list
  - https://developers.google.com/calendar/api/v3/reference/calendarList/list
  - projects/atender/.designs/20260528-v8-google-calendar-oauth.md
related_knowledge:
  - knowledge/pattern/better-auth-incremental-scope-and-cron-token.md
  - projects/atender/.knowledge/07-google-calendar-oauth-integration.md
  - knowledge/pattern/ics-import-hash-dedup-preview-commit.md
---

## Context

ユーザーが個人 Google Calendar を「ルーム」「グループ」「プロジェクト」等の単位に紐づけて取り込みたい場面。ユースケース例:

- Atender: 学生がスマホ予定をルームメンバーに「予定あり」として共有
- 予約 SaaS: 個人の Google 予定を「Busy」として予約画面に反映
- グループウェア: メンバーの予定を集約表示

「1 ユーザー = 1 Google アカウント連携」と「1 ルーム × N カレンダー」の関係を**別 model に分離**して保持する。

## What

### Schema (Prisma + SQLite)

```prisma
model GoogleCalendarConnection {
  id            String              @id @default(cuid())
  userId        String
  accountId     String              // better-auth Account.id
  googleEmail   String
  scope         String              // space-separated
  status        GoogleConnStatus    @default(ACTIVE)
  lastError     String?
  lastSyncedAt  DateTime?
  // ...
  syncs         GoogleCalendarSync[]

  @@unique([userId])      // 1 user = 1 connection (MVP)
  @@unique([accountId])
}

enum GoogleConnStatus { ACTIVE  REVOKED  ERROR }

model GoogleCalendarSync {
  id                String                    @id @default(cuid())
  connectionId      String
  roomId            String
  googleCalendarId  String                    // "primary" or "<id>@group.calendar.google.com"
  calendarSummary   String
  calendarTimeZone  String
  visibilityMode    EventVisibility           @default(TITLE_MAPPED)
  syncToken         String?                   // incremental sync 用
  status            GoogleSyncStatus          @default(IDLE)
  lastError         String?
  lastSyncedAt      DateTime?
  enabled           Boolean                   @default(true)
  // ...
  events            RoomEvent[]               @relation("RoomEventGoogleSync")

  @@unique([roomId, connectionId, googleCalendarId])
  @@index([connectionId, enabled])
  @@index([status, lastSyncedAt])
}

enum GoogleSyncStatus { IDLE  SYNCING  OK  FAILED  REVOKED }

model RoomEvent {
  // ... 既存 (MANUAL / ICS 由来も保持) ...
  googleSyncId          String?
  googleEventId         String?
  googleRecurringEventId String?

  @@unique([googleSyncId, googleEventId])
  @@index([googleSyncId])
}
```

### 同期 (events.list with syncToken)

```ts
// 初回 (syncToken なし)
GET /calendar/v3/calendars/{id}/events
  ?singleEvents=true       // RRULE を Google が展開
  &orderBy=startTime
  &timeMin=<now>
  &timeMax=<now+6m>
  &maxResults=2500

// 2 回目以降 (syncToken あり)
GET /calendar/v3/calendars/{id}/events
  ?syncToken=<prev>        // 差分のみ、timeMin/Max は付けられない

// 最終ページに含まれる nextSyncToken を保存
// 410 GONE が返ったら全削除 → full re-sync 即実行
```

### 設計の要点

1. **Connection と Sync の責務分離**: Connection は「OAuth 関係」、Sync は「room × calendar の取り込み単位」。連携解除で Sync は全削除、RoomEvent は option で残せる
2. **sync の mutex は status=SYNCING を兼用**: 別の lock テーブルを作らない。runSync 先頭で `SYNCING` の sync は skip
3. **dedup key は `(googleSyncId, googleEventId)`**: singleEvents=true で展開された instance が個別 id を持つので衝突しない。同一 Google event を別 sync (= 別ルーム) で取り込めば別行として保存
4. **recurrenceRule は null で保存**: Google が singleEvents=true で展開済の instance を返すので、自前 RRULE 展開ロジックを呼ばない。`recurringEventId` だけ保持して「親 ID」が分かる状態にする
5. **cancelled は deleteMany**: events.list が `status: "cancelled"` で返した event は対応 RoomEvent を削除
6. **DESCRIPTION / LOCATION / ATTENDEE は破棄**: プライバシー優先 (= Calendly 同等方針)
7. **all-day event は calendar.timeZone の壁時計 00:00 として UTC 化**: dayjs.tz(date + " 00:00:00", tz) で扱う。end.date は exclusive (翌日) なので -1ms 補正
8. **cron は外部 scheduler (Coolify scheduled task) + tsx スクリプト**: プロセス内 node-cron は dev/多重起動で重複事故が起きやすい。`pnpm --filter @atender/api exec tsx scripts/sync-google-calendars.ts` を 1h 周期で打つ

### タイトル正規化との統合

User 単位の title rule (例: Atender の `IcsTitleRule`) を ICS import と Google 同期で共通利用する。同期サービスから `applyTitleRules(event.summary, userRules)` を呼ぶだけ。rule が hit したら rule.visibilityMode、しなければ sync.visibilityMode を採用。

```ts
const applied = applyTitleRules(rawTitle, userRules);
const visibilityMode = applied.ruleId != null ? applied.visibilityMode : sync.visibilityMode;
```

これで「全ルーム共通の title 正規化ルール × ルーム別の visibility default」が両立する。

## Why

- 「ユーザー単位の OAuth 連携」と「ルーム単位の取り込み制御」は責務が違うので 1 model に押し込まない方が見通しが良い
- Connection を user-unique にすると schema がシンプル、複数アカウントは将来追加
- syncToken による incremental sync は Google API quota を 99% 削減 (初回 fetch 後は差分のみ)
- DESCRIPTION 破棄 / visibility enum 既定 = TITLE_MAPPED でプライバシー対策が default ON
- 同一 event を別ルームに紐づけて表示するユースケース (= ユーザーが意図的に複数ルームに同期) も dedup key の設計で自然に扱える

## How to apply

- 新規 PJ で「個人 Google Cal を集団に共有する」UI を作るとき、Connection (user-unique) と Sync (room x cal) の 2 段 model を最初から組む
- syncToken は **最終ページに含まれる nextSyncToken** のみ採用 (途中ページの nextPageToken と混同しない)
- 410 GONE は **必ず** full re-sync する経路を用意 (1 週間以上未使用で syncToken expire)
- runSync の mutex は `status=SYNCING` で十分。分散 lock (Redis 等) は Single container では不要
- visibility 階層は (rule hit ? rule.visibility : sync.default) のように rule 優先
- 連携解除は「予定残す / 削除する」の 2 択モーダルが UX 上ベスト (Atender は default = 削除)
- cron は外部 scheduler 推奨。Coolify scheduled task / Render Cron / Vercel Cron 等
- Webhook (Watch API) は MVP では採用せず polling から始める。channel 期限 / 再購読 cron / 署名検証で実装コストが 3 倍

## 関連

- [[pattern/better-auth-incremental-scope-and-cron-token]] — token 取得経路 (前提)
- [[pattern/ics-import-hash-dedup-preview-commit]] — .ics import との並走パターン
- [[pattern/rrule-string-onfly-expand-with-overrides]] — 自前 RRULE 展開 (Google は不要だが、ICS import 側で使う)
