---
title: EventKit (iOS 17+) — 権限分離・カレンダー/イベント識別子の安定性・双方向同期の要点
category: library
tags: [ios, eventkit, calendar, sync, swift]
created: 2026-07-23
project: global
sources:
  - "iPhoneOS26.5.sdk EventKit.framework Headers (EKEventStore.h / EKCalendarItem.h / EKEvent.h / EKCalendar.h) — 一次ソース"
  - "https://developer.apple.com/documentation/eventkit/ekcalendaritem/calendaritemexternalidentifier"
  - "https://developer.apple.com/documentation/eventkit/ekeventstore/calendaritems(withexternalidentifier:)"
  - "https://developer.apple.com/forums/thread/6636"
  - "https://developer.apple.com/documentation/eventkit/ekeventstore/requestwriteonlyaccesstoevents(completion:)"
  - "https://developer.apple.com/documentation/eventkit/ekcalendar/init(for:eventstore:)"
  - "https://developer.apple.com/library/archive/qa/qa1926/_index.html"
  - "https://oleb.net/blog/2012/05/creating-and-deleting-calendars-in-ios/"
---

## Context
iOS ネイティブアプリから iPhone/iCloud のローカルカレンダー (EventKit) と双方向同期する設計をするとき。iOS 17 で権限モデルが full/write-only に分離された後の実在 API・availability・識別子の安定性を SDK ヘッダ一次ソースで確定した (iOS 26.5 SDK 実測)。

## What
**権限モデル (iOS 17 で分離)** — 全て `EKEntityType.event` 前提:
- `requestFullAccessToEvents(completion:)` — `API_AVAILABLE(ios(17.0))`。読み書き両方。async 版もブリッジされる。
- `requestWriteOnlyAccessToEvents(completion:)` — `ios(17.0)`。追加専用 (既存イベントを読めない)。双方向同期には **full access が必須**。
- `requestAccess(to:completion:)` (旧) — `API_DEPRECATED(ios(6.0, 17.0))`。iOS 17 で deprecated。iOS 17 未満をサポートするなら `#available` 分岐で旧 API 併用が必要 (atender は iOS 17+ target なので新 API 一本で可)。
- 現在値照会は `EKEventStore.authorizationStatus(for:)` (旧名 `authorizationStatusForEntityType:`, iOS 6+)。iOS 17 で `.fullAccess` / `.writeOnly` ケースが追加。
- **Info.plist キー**: full = `NSCalendarsFullAccessUsageDescription`、write-only = `NSCalendarsWriteOnlyAccessUsageDescription` (iOS 17+)。旧 `NSCalendarsUsageDescription` は後方互換用。

**列挙・読み・書き**:
- 列挙: `calendars(for: .event)` (旧名 `calendarsForEntityType:`, iOS 6+)。新規作成先のデフォルトは `defaultCalendarForNewEvents`。
- 読み: `predicateForEvents(withStart:end:calendars:)` → `events(matching:)` (どちらも古くから安定)。`calendars` に nil を渡すと全カレンダー対象。
- 書き: `EKEvent(eventStore:)` 生成 → `save(_:span:commit:)` (iOS 5+)、削除 `remove(_:span:commit:)`。`span` は `.thisEvent` / `.futureEvents` (繰り返し対応)。
- 変更検知: `EKEventStoreChangedNotification` (`NSNotification.Name.EKEventStoreChanged`)。**外部プロセス・別 store・自分の save/remove すべてで発火する** (= 自分の書き込みでも飛ぶ → echo ループ源)。受信時は保持している EKEvent を全て無効とみなし再フェッチ推奨。権限変更でも飛ぶ。

**★ 識別子の安定性 (双方向同期の要・ヘッダ逐語)**:
- `EKEvent.eventIdentifier` — ローカル参照用の一意 ID。だが **カレンダー移動や sync 操作で ID が変わりうる** (ヘッダ明記)。永続キーには不適。
- `EKCalendarItem.calendarItemExternalIdentifier` — サーバ提供の外部 ID。**複数デバイス間で同一イベントを指す**。**繰り返しイベントの全 occurrence で同じ値** (occurrence 区別には start date を併用)。ローカル/iCloud カレンダーでは `calendarItemIdentifier` にパススルー。**ただし重複コピーが同一 DB 内に存在しうる** (ICS を複数カレンダーにインポート / 共有カレンダー招待 / delegate / 複数アカウント購読) → 取得は配列を返す `calendarItems(withExternalIdentifier:)`。**Exchange では sync 後に値が変わる報告あり** (forum/6636)。iCloud なら比較的安定。
- `EKCalendar.calendarIdentifier` — **sync-proof ではない。フルシンク/再ログインで失われる** (ヘッダ明記)。どのカレンダーと同期するかの永続保存に単独使用は危険 → title/type/color/source をバックアップキーにする。

**バックグラウンド制約**: EventKit にバックグラウンド配信の仕組みは無い。`EKEventStoreChangedNotification` は前面時に届く前提。定石は「アプリ起動/前面化時に `refreshSourcesIfNecessary()` → 差分再取得」。

**★ アプリ専用カレンダーの新規作成 (シフトボード方式)**:
- 生成: `EKCalendar(for: .event, eventStore: store)` (ObjC `+calendarForEntityType:eventStore:`, iOS 6+)。`title` / `cgColor` を設定し **`source` を必ずセット** (未設定で保存すると `EKErrorCalendarHasNoSource`)。保存は `store.saveCalendar(_:commit:)` (Swift では `throws`)。削除は `store.removeCalendar(_:commit:)` — **カレンダー内の全イベントごと消える**。
- **source の選び方**: `store.defaultCalendarForNewEvents?.source` を第一候補にする (iCloud が有効なら iCloud source、無ければローカルが返る)。`sourceType == .calDAV` かつ `title == "iCloud"` での判定は **title がユーザー編集可能なので不可**。`sourceType == .local` 決め打ちも不可 — **TN QA1926: リモートアカウント (iCloud 等) が有効だと「空のローカルカレンダー」は非表示にされ、イベントを持つローカルカレンダーは移行/削除を促される**。→ 専用カレンダーをローカル source に作ると「作ったのに標準カレンダー App に出ない」になる。
- 保存に失敗しうる source: `EKErrorSourceDoesNotAllowCalendarAddDelete` (購読/誕生日など追加不可アカウント)、`EKErrorSourceDoesNotAllowEvents`。エラーは握り潰さず UI に出す。
- **永続化**: 作成後の `calendarIdentifier` を UserDefaults 等に保存。ただし `calendarIdentifier` は sync-proof でない (上記) + **ユーザーが標準カレンダー App から削除できる** → 起動時に `store.calendar(withIdentifier:)` が `nil` を返したら「消えた」と判定し、**title 一致で再探索 → 見つからなければ再作成**、のフォールバックを必ず持つ。EventKit に「カレンダー削除イベント」は無く、`EKEventStoreChanged` 通知後の再照会が唯一の検知手段。
- **write-only access では専用カレンダー方式は成立しない**。公式 doc 逐語: 「your app receives write-only access... it can't access any of the existing calendars and events on the device, **including events your app created**. API calls to read event data from the event store don't return any events」。= 作成済みカレンダーの再取得 (`calendar(withIdentifier:)` / `calendars(for:)`) ができず、毎回「見つからない → 再作成」に陥る。**専用カレンダーを使うなら full access 必須**。

## Why
iOS 17 のプライバシー強化で「予定を書き込むだけ」のアプリに全読み取り権限を求めさせない設計になった。識別子が3種あるのは責務が違うから: `eventIdentifier`=ローカル即時参照 (揮発的)、`calendarItemExternalIdentifier`=デバイス跨ぎの同一性 (準永続だが重複あり)、`calendarIdentifier`=カレンダー参照 (フルシンクで消える)。

## How to apply
- 双方向同期の永続キーは `calendarItemExternalIdentifier` を第一候補にする。ただし (1) 重複しうる → calendar/source で絞る、(2) recurring は全 occurrence 同値 → start date 併用、(3) Exchange は不安定 → iCloud/local 前提に留める、を設計に明記。
- サーバ DB 側にミラー行を持つなら `{ekExternalId, ekCalendarId, startDate}` を保持し、`eventIdentifier` は「今この瞬間の再フェッチ用」に限定 (永続保存しない)。
- カレンダー選択は `calendarIdentifier` を保存しつつ、消えた時のフォールバック (title/source 一致) を用意。
- echo ループ回避: 自分の save/remove でも `EKEventStoreChangedNotification` が飛ぶので、「サーバ由来で今書いた ekExternalId のセット」を短時間覚えておき、その通知起因の再取り込みを抑止する。加えて lastModifiedDate / 自前 version でどちらが新しいか判定。
- iOS 17+ target なら full/write-only 新 API 一本でよい。双方向なら full 一択。
