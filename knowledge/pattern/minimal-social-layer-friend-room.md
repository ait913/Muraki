---
title: 最小限の SNS レイヤ (Friend + Room) を Prisma + 単一 endpoint で設計するパターン
category: pattern
tags: [prisma, sqlite, social, friendship, room, group, invite-link, status-enum]
created: 2026-05-26
project: global
sources:
  - Atender Phase 4 設計 doc (.designs/20260526-v3-rooms-friends.md)
  - https://www.vertabelo.com/blog/database-model-for-social-networking-site/
  - https://support.timetreeapp.com/hc/ja/articles/204273015
  - https://penmark.jp/news/2024/07/04/v3-0-0/
---

## Context

「友達追加 + グループ (ルーム) + 共有カレンダー」程度の軽量 SNS 機能を、既存アプリに**追加機能として後付け**するときの最小構成。LINE / Penmark / TimeTree のような **個人 ID + 招待リンク + 一方向申請** 流のモデル。

学生向けアプリ (Atender)、メンバー数 4-10 人規模のルーム、リアルタイム通信なし (polling で十分)、SQLite + Prisma という制約下での実証パターン。

## What

### 1. Friendship は単一テーブル + status enum (双方向 Edge x2 不採用)

```prisma
enum FriendshipStatus {
  PENDING
  ACCEPTED
  DECLINED
  BLOCKED
}

model Friendship {
  id         String           @id @default(cuid())
  senderId   String
  receiverId String
  status     FriendshipStatus @default(PENDING)
  createdAt  DateTime         @default(now())
  acceptedAt DateTime?

  @@unique([senderId, receiverId])
  @@index([receiverId, status])
  @@index([senderId, status])
}
```

- `(senderId, receiverId)` で**同方向**の重複防止。逆方向 (相手→自分) が独立行として作られうるため、**Service 層で「逆方向に PENDING があれば自動 ACCEPTED に昇格」** で吸収
- `BLOCKED` は `senderId=blocker, receiverId=blocked` に正規化。block 時に既存の逆方向行も統合
- `DECLINED` 後の再申請は同一行を `PENDING` に戻す UPDATE (新規 INSERT ではなく)

### 2. Room は `Room + Membership + Event` + `inviteCode` 直書き

```prisma
enum RoomRole { OWNER MEMBER }

model Room {
  id              String   @id @default(cuid())
  name            String
  inviteCode      String   @unique @default(cuid())
  inviteExpiresAt DateTime?
  createdByUserId String
  // ...
}

model RoomMembership {
  roomId String
  userId String
  role   RoomRole @default(MEMBER)
  @@unique([roomId, userId])
}

model RoomEvent {
  roomId   String
  authorId String
  title    String
  start    DateTime
  end      DateTime
  isAllDay Boolean
  @@index([roomId, start])
}
```

- 招待は `Room.inviteCode` を URL に乗せて遷移 (TimeTree 流)。手入力 / QR は Phase 後送り
- 再発行 = inviteCode の UPDATE (新 cuid)、旧リンクは即無効
- `RoomInvite` 別テーブル化は「複数同時招待 / 期限ごと履歴」が要るまで保留

### 3. 招待リンク route を Friendship と Room で揃える

```
/friends/add/$inviteCode    →  POST /api/friendships { receiverInviteCode } → 申請 → /friends へ replace
/rooms/join/$inviteCode     →  POST /api/rooms/join { inviteCode }          → 即参加 → /rooms/:id へ replace
```

未認証なら `/signin?redirect=...` に飛ばす。`replace navigate` で履歴に招待 URL を残さない (back キーで重複申請を防ぐ)。

### 4. 共有カレンダー + 空き時間は単一 endpoint + クライアント集計

```
GET /api/rooms/:id/week?weekStart=YYYY-MM-DD
→ { members[], meetings[]: 全メンバーの該当週分, roomEvents[]: 該当週分 }
```

- 1 リクエストで週分一括取得
- 「空き時間」はクライアントで boolean matrix を組んで free count を出す (`free[d][p] = members.filter(!busy).length`)
- フィルタ (人選び) も UI 側完結、再 fetch なし
- サーバ側は raw データを返すだけ

### 5. status code の規約 (Friendship / Room 共通)

| status | 用途 |
|---|---|
| 401 | 未認証 |
| 403 | NOT_OWNER / NOT_RECEIVER / NOT_SENDER (権限不足) |
| 404 | USER_NOT_FOUND / INVITE_NOT_FOUND / NOT_MEMBER (存在を露呈しない) |
| 409 | ALREADY_FRIEND / ALREADY_MEMBER / SELF_FRIENDSHIP / NOT_PENDING / OWNER_CANNOT_LEAVE |
| 410 | INVITE_EXPIRED |

「他人の id を直接叩く」攻撃ベクトルに対しては **一律 404** で漏らさない (403 と 404 を混ぜると存在判定に使われる)。

## Why

- 単一テーブル + status enum は SQLite / Prisma の制約下で transaction 数を最小化できる (1 UPDATE で状態遷移完結)
- 招待リンク直書きは MVP の Time-to-First-Friend を最短化。LINE 共有が圧倒的主流の前提
- 単一 endpoint 集約は TanStack Query のキャッシュキーが 1 つで済み、invalidate 設計が単純化 (`["rooms", id, "week", *]`)
- クライアント集計は「3 人だけの空き時間」「人を 1 人除いた空き時間」のような対話的フィルタを再 fetch なしで実現
- ★ status code の 403/404 使い分けで「相手が自分をブロックしているか」が漏れない (Friendship `POST` で相手が自分を BLOCKED していたら 404 USER_NOT_FOUND で返す)

## How to apply

新規プロジェクトで「軽量な友達 / グループ」を実装したいとき:

1. Friendship は **1 テーブル + status enum**。一方向式 (sender = 申請者) を採用、Edge x2 は不採用
2. Service 層で **逆方向 PENDING → 自動 ACCEPTED 昇格**、**DECLINED → 再申請で PENDING 復帰** の挙動を実装
3. Room / Group は **role enum (OWNER/MEMBER) + Membership + 招待コード直書き**。最初から RoomInvite テーブルを分けない
4. 招待は **URL タップで遷移する route** (`/<feature>/<action>/$code`) + `POST /api/<feature>/join` を作る。手入力フィールドは省略
5. 「みんなの空き時間」「全員のスケジュール統合」は **単一 endpoint で raw データ一括取得 + クライアント集計**。サーバで集計しない (フィルタ要件が変わると endpoint が増殖する)
6. **status code の 401/403/404/409/410 を明示**。Service 層から throw する `AppError(status, code, details?)` を統一フォーマットで
7. Pre-design リサーチ時に必ず: 双方向 vs 一方向式 / 招待リンク仕様 / 集計のサーバ vs クライアント / TanStack Query invalidation key の 4 つを決め打ちしてから API 設計に入る

不採用案 (再検討しない):
- 双方向 Edge x2 (整合性管理が複雑)
- ペア正規化 (min, max) (一方向式なら不要)
- サーバ側集計 endpoint (フィルタで API 再叩き発生)
- RoomInvite 別テーブル化 (Phase 5 送り)
- WebSocket / SSE (polling で十分、MVP 範囲外)
