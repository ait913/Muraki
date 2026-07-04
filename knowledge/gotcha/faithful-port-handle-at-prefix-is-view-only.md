---
title: 忠実移植で handle の "@" 前置はView層限定 (データ/純粋ロジックは生handle)
category: gotcha
tags: [ios-port, faithful-port, subtitle, handle, member-name, atender]
created: 2026-07-01
project: atender
sources: [".designs/20260701-ios-port-phase-d-rooms-friends.md", "apps/web/src/lib/meetingExpansion.ts", "apps/web/src/components/rooms/RoomTimetable.tsx"]
---

## Context
Atender iOS Phase D の RoomCalendarLogic.buildCalendarEvents / RoomTimetableLogic.buildEvents で、
メンバー名の subtitle フォールバックを検証したら 2 テストが RED。
期待 "alice" に対し実装は "@alice" を返した (member.name が nil で handle にフォールバックした場合)。

## What
表示名フォールバックの正典は `name ?? handle ?? "No name"` で **handle は生値** (@ を付けない)。
- Web 正典: `lib/meetingExpansion.ts:135` (memberName) / `:157` (authorName) / `RoomTimetable.tsx:59` / `AvailabilityBar.tsx:77` すべて `?? member.handle ??` を @ なしで使う。
- 設計doc の純粋ロジック契約も `subtitle = member.name ?? handle ?? "No name"` と明記。
- 一方 "@" は **View層の装飾**にすぎない: `FriendCard.tsx` は `Text("@\(handle)")` と表示側で付ける。
iOS 実装は共通ヘルパ (memberName(name:handle:)) が handle フォールバックに "@" を前置してしまい、データ/純粋ロジック層に View 装飾が漏れた。

## Why
「@handle は人間可読の慣習」という直感で、名前生成ヘルパに @ を混ぜたくなる。
だが忠実移植では「データ層が生む文字列 = Web のデータ層が生む文字列」でなければならず、
@ の有無はスナップショット/subtitle 比較で 1:1 不一致になる。
影響は name 欠落メンバーのみだが、忠実移植プロジェクトでは spec 逸脱として RED 相当。

## How to apply
- Architect: 純粋ロジックの subtitle/表示名契約を書くとき「handle は生値、@ はView層」と明示する。
- Developer: 名前フォールバックヘルパ (memberName 等) に @/装飾を入れない。@ は Text/ラベル側で付ける。
- Reviewer: name=nil・handle有り のケースを必ずテストに含める (デモデータは name 埋まりがちで見逃す)。
- 修正は memberName ヘルパの handle 分岐から "@" を除くだけの1行。
