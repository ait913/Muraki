---
title: EventKit の繰り返しモデル — RRULE 表現力・例外(detached)・span・occurrence 展開
category: library
project: global
tags: [ios, eventkit, calendar, recurrence, rrule, rfc5545, swift]
created: 2026-07-29
sources:
  - "iPhoneSimulator26.5.sdk EventKit.framework Headers (EKRecurrenceRule.h / EKRecurrenceEnd.h / EKEvent.h / EKEventStore.h / EKCalendarItem.h / EKAlarm.h / EKStructuredLocation.h) — 一次ソース (逐語)"
  - https://developer.apple.com/documentation/eventkit/retrieving-events-and-reminders
  - https://developer.apple.com/documentation/eventkit/creating-events-and-reminders
  - https://developer.apple.com/documentation/eventkit/ekevent/isdetached
  - https://datatracker.ietf.org/doc/html/rfc5545
related_knowledge:
  - knowledge/library/eventkit-ios17-access-and-sync-identifiers.md
---

## Context

iOS アプリで「予定の繰り返し」を扱い、それを EventKit (iPhone 標準カレンダー) と同期する設計をするとき。
「RRULE をどこまで持てるか」「この回だけ変更/削除をどう表現するか」を SDK ヘッダ一次ソースで確定した (iOS 26.5 SDK 実測)。

## What

**EKRecurrenceRule で表現できる RRULE (ヘッダ `EKRecurrenceRule.h` の逐語対応)**

| RRULE | EventKit | 制約 (ヘッダ明記) |
|---|---|---|
| FREQ | `frequency` (daily/weekly/monthly/yearly) | 必須 |
| INTERVAL | `interval` | 0 を渡すと **例外送出** |
| BYDAY | `daysOfTheWeek: [EKRecurrenceDayOfWeek]` (序数付き可) | weekly/monthly/yearly のみ。**daily では無視** |
| BYMONTHDAY | `daysOfTheMonth` (±1..31) | **monthly のみ**。他は無視 |
| BYMONTH | `monthsOfTheYear` (1..12) | **yearly のみ** |
| BYWEEKNO | `weeksOfTheYear` (±1..53) | **yearly のみ** |
| BYYEARDAY | `daysOfTheYear` (±1..366) | **yearly のみ** |
| BYSETPOS | `setPositions` (±1..366) | 上記 BY* のいずれかが在るときのみ有効 |
| WKST | `firstDayOfTheWeek` (0=未設定, 1=日..7) | **readonly**。「interval>1 の weekly でのみ展開に影響」「framework が 2(月) を設定する」 |
| COUNT / UNTIL | `EKRecurrenceEnd` | **排他**。count 版は endDate=nil、date 版は occurrenceCount=0 を返す。**同時指定不可** |
| BYHOUR / BYMINUTE / BYSECOND | **無し** | API 自体が存在しない |

- `EKRecurrenceRule` は **immutable** (「It is currently not possible to directly modify a EKRecurrenceRule or any of its properties」)。変更は新規生成 → `event.recurrenceRules = [新]` → save。
- `recurrenceRules` は**配列**なので複数 RRULE を持てる (RFC 上も可)。UI で扱うなら 1 本に固定するのが定石。
- ヘッダ注記: 「certain combinations make no sense and **will be ignored**」— 不正組合せはエラーにならず**黙って無視される**。バリデーションはアプリ側の責務。

**★ EXDATE / RDATE / RECURRENCE-ID に対応する API は EventKit に存在しない** (全ヘッダ grep で 0 件)。
代替は「occurrence を取得して span 付きで save/remove する」= EventKit が内部で例外を作る、という手続き型モデルのみ。
→ **RFC5545 の例外セット (EXDATE/RDATE) を EventKit から読み出す手段が無い**。サーバ側で EXDATE を正典に持つ設計は EventKit と往復できない。

**occurrence 展開**
- `EKEvent` = 「an occurrence of an event」(EKEvent.h ヘッダ冒頭の abstract 逐語)。マスタ 1 件ではなく**各回が別 EKEvent** として返る。
- 裏付け: `event(withIdentifier:)` は「If it is a recurring event, this method will **return the first occurrence** of the event」(公式 doc 逐語)。`EKEvent.occurrenceDate` は「the date on which this event was **originally scheduled** to occur … 変更後も不変」= RECURRENCE-ID 相当。
- `predicateForEvents(withStart:end:calendars:)` は **最大 4 年**しか見ない (超えると先頭 4 年に切り詰め、doc 明記)。無限繰り返しでも安全だが、4 年超のレンジを渡す設計は不可。
- **繰り返しの全 occurrence は `calendarItemExternalIdentifier` が同値**。occurrence の識別には start / `occurrenceDate` の併用が必須。

**例外 (この回だけ) の表現**
- 変更: 取得した occurrence の属性を書き換え `save(_:span:.thisEvent)` → その回が **detached** になる。`isDetached` は「part of a repeating event **and one or more of its attributes have been modified**」のとき true (doc 逐語)。
- 削除: `remove(_:span:.thisEvent)` でその回だけ消える (= EXDATE 相当)。
- `.futureEvents`: 「your changes can apply to **all future occurrences**」/ 「you can **remove all future occurrences**」(doc 逐語)。**過去回は保持される**。
- **「この回以前」「全部」を直接指定する span は無い** (`EKSpan` は `.thisEvent` / `.futureEvents` の 2 値のみ)。「全部」を表現したいなら series の最初の occurrence に `.futureEvents` を当てる。

**その他 (普通のカレンダーアプリに要る項目)**
- アラート: `EKCalendarItem.alarms: [EKAlarm]?` / `addAlarm(_:)`。`EKAlarm.alarmWithRelativeOffset:` (負値 = 開始前) と `alarmWithAbsoluteDate:` の 2 種。**複数可**だが「Calendars may allow a certain maximum number of alarms. When this item is saved, it will **truncate any extra alarms**」(ヘッダ逐語) — 上限は保存先カレンダー依存で、超過分は**黙って切られる**。
- 場所: `location: String?` (EKCalendarItem) と `structuredLocation: EKStructuredLocation?` (iOS 9+)。ヘッダ逐語で「the getter for location just **returns the structured location's title**」「setter は `setStructuredLocation:[EKStructuredLocation locationWithTitle:…]` と等価」= **同じ 1 個の値の 2 面**であって別フィールドではない。geo 座標/半径 (ジオフェンス) が要る時だけ structured 側を使う。
- 他: `notes` / `URL` / `timeZone` / `availability` (busy/free/tentative/unavailable) / `status` (read-only、実用は cancelled のみ)。
- UI 部品: `EventKitUI` に `EKEventEditViewController` / `EKEventViewController` / `EKCalendarChooser` が実在 (SDK 26.5 で確認)。標準の編集 UI (繰り返しピッカー込み) を丸ごと借りられる。

## Why

EventKit は RFC5545 の**宣言的**な例外モデル (EXDATE/RDATE/RECURRENCE-ID) を API として露出せず、
「occurrence を掴んで span 付きで書く」**手続き的**モデルだけを提供する。
双方の間には片道の情報損失があり、サーバ側 DB を RFC5545 形式で正典にすると往復で壊れる。

## How to apply

- 自前 DB に RRULE 文字列を持つ設計自体は EventKit と両立する (FREQ/INTERVAL/BYDAY/BYMONTHDAY/BYMONTH/BYSETPOS/COUNT/UNTIL は相互変換可)。
- ただし **例外 (この回だけ変更/削除) の往復は非対称**: 自前 → EventKit は span で書けるが、EventKit → 自前は「展開済み occurrence の差分」でしか観測できない。設計では **occurrence 単位のミラー行**を持つか、例外を「自前側だけの概念」に閉じるかを先に決める。
- COUNT と UNTIL を UI で同時に出さない (EKRecurrenceEnd が排他)。
- 取得レンジは 4 年以内に切る。
- アラートは「保存時に黙って切り捨てられうる」ので、保存後に read-back して実際に何個残ったか確認する。
- 標準の編集体験でよければ `EKEventEditViewController` を出す方が、繰り返し UI を自前実装するより速く HIG 準拠になる。
