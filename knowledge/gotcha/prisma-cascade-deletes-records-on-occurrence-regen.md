---
title: occurrence の delete→regen は onDelete:Cascade で子レコードを道連れにする
category: gotcha
tags: [prisma, cascade, sqlite, attendance, occurrence, data-loss]
created: 2026-06-11
project: atender
sources:
  - Atender apps/api/prisma/schema.prisma (AttendanceRecord.occurrence onDelete:Cascade)
  - Atender apps/api/src/services/occurrenceGen.ts (reconcileOccurrencesForSemesterDateChange)
  - Atender apps/api/src/services/meeting.service.ts (既存の delete→regen パターン)
  - Atender .designs/20260611-semester-edit-and-tweaks.md
---

## Context

時間割アプリで「授業実体 (MeetingOccurrence) を日付範囲から再生成する」操作が複数ある (時間割編集・学期日付変更)。occurrence には出席記録 (AttendanceRecord) が `occurrenceId` で 1:1 紐づき、リレーションは `onDelete: Cascade`。

既存の唯一の再生成パターン (`meeting.service.ts`) は `occurrence.deleteMany({meetingId}) → 作り直し` の素朴な全消し。これを「学期の開始/終了日を後から縮める」操作に流用しようとした。

## What

**occurrence を deleteMany すると、紐づく AttendanceRecord が Cascade で物理削除される。** 全消し→regen を日付変更に流用すると、範囲内の occurrence も一度消えるため**学期内の出席記録が全部消える**。regen は occurrenceId を再採番するので「同じ日付で作り直すから記録も復活」もしない (records は既に消えている)。

回避した実装 (`reconcileOccurrencesForSemesterDateChange`):
- **広げる方向**: 新範囲で `generateOccurrencesForMeetings` を呼ぶだけ。`@@unique([meetingId, date, periodOffset])` があり P2002 を skip 吸収するので既存行は壊さず増分追加のみ
- **縮める方向**: 範囲外 occurrence を `findMany({ where: 範囲外, select: { id, attendanceRecord } })` で引き、**`attendanceRecord == null` の id だけ** `deleteMany({ id: { in } })`。記録のある occurrence は範囲外でも温存 (overview の日付ループから見えなくなるだけ。DB に残り、再度広げれば復活)
- ★ **範囲条件で直接 `deleteMany({ where: { date: 範囲外 } })` は禁止** — 記録ありを巻き込み Cascade が発火する

## Why

`onDelete: Cascade` は「親を消したら子も消す」を DB/Prisma が無条件に実行する。再生成ロジックの "delete" が範囲内の記録ある行に触れた瞬間、ユーザーの入力データ (出席記録) が静かに消える。テストで気づきにくい (occurrence の件数だけ見ていると records の消失を見逃す)。

## How to apply

- occurrence (や子レコードを Cascade で持つ親) を「作り直す」操作を書くときは、**全消し→regen を即座に疑う**。子レコードのある行を delete 対象から除外する reconcile 方式にする
- 削除対象は「不要 かつ 子レコードなし」の id を明示列挙してから `deleteMany({ id: { in } })`。`where` で範囲・属性条件を直接 delete に使わない
- レビューは occurrence 件数でなく**子レコード (AttendanceRecord) の件数が縮小操作後も不変**を直接アサートする (negative control: 全消し実装なら records が 0 になって落ちる)。Atender ではこの統合テストで保護を実証した
- 関連: 出席率計算の母数・未記録の扱いは [[attendance-to-date-rate-and-allowed-absences]]
