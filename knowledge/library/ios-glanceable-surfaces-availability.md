---
title: iOS の「一瞥」表示面 (Widget / Live Activity / Dynamic Island) の実在 API と最低バージョン
category: library
project: global
tags: [ios, swiftui, widgetkit, activitykit, live-activity, dynamic-island, glanceable, availability]
created: 2026-07-17
sources:
  - https://developer.apple.com/tutorials/data/documentation/activitykit/activity.json
  - https://developer.apple.com/tutorials/data/documentation/activitykit/activity/request(attributes:content:pushtype:).json
  - https://developer.apple.com/tutorials/data/documentation/activitykit/activity/pushtostarttoken.json
  - https://developer.apple.com/tutorials/data/documentation/widgetkit/dynamicisland.json
  - https://developer.apple.com/tutorials/data/documentation/widgetkit/widgetfamily/accessorycircular.json
  - https://developer.apple.com/tutorials/data/documentation/swiftui/button/init(intent:label:).json
  - https://developer.apple.com/tutorials/data/documentation/swiftui/view/scrolltargetbehavior(_:).json
  - https://developer.apple.com/tutorials/data/documentation/swiftui/pagingscrolltargetbehavior.json
  - https://developer.apple.com/tutorials/data/documentation/swiftui/pagetabviewstyle.json
  - https://developer.apple.com/tutorials/data/documentation/uikit/uiscreen/main.json
  - https://developer.apple.com/tutorials/data/design/human-interface-guidelines/live-activities.json
  - https://developer.apple.com/tutorials/data/design/human-interface-guidelines/widgets.json
---

## Context

「移動中・片手・数秒」で情報を出す iOS の面 (ウィジェット / Live Activity / Dynamic Island) を設計に載せる前の実在確認。
値はすべて `developer.apple.com/tutorials/data/documentation/<path>.json` の `metadata.platforms` 実測 (2026-07-17)。
Xcode の SDK `.swiftinterface` の `@available` とも突合済で一致。

## What

### 実在 API と iOS 最低バージョン (実測)

| API | iOS introduced | deprecated | 用途 |
|---|---|---|---|
| `WidgetKit.WidgetFamily` / `TimelineProvider` | **14.0** | — | ホーム画面ウィジェット |
| `WidgetFamily.accessoryCircular` 等 accessory 系 | **16.0** | — | ロック画面ウィジェット |
| `ActivityKit.Activity` / `ActivityAttributes` / `activityState` | **16.1** | — | Live Activity 本体 |
| `WidgetKit.DynamicIsland` | **16.1** | — | Dynamic Island 表示 |
| `Activity.request(attributes:content:pushType:)` | **16.2** | — | Live Activity 開始 |
| `SwiftUI.Button.init(intent:label:)` | **17.0** | — | **インタラクティブ ウィジェット** |
| `View.scrollTargetBehavior(_:)` / `PagingScrollTargetBehavior` / `.paging` | **17.0** | — | ページング スクロール |
| `View.scrollTargetLayout(isEnabled:)` / `scrollPosition(id:anchor:)` | **17.0** | — | ページング補助 |
| `Activity.pushToStartToken` | **17.2** | — | push で Live Activity 開始 |
| `TabView` + `PageTabViewStyle` | 14.0 | **非推奨ではない** (2026-07 時点) | 旧来のページング |
| `UIScreen.main` | 2.0 | ★ **26.0 で deprecated** | 画面サイズ取得 |

→ **deployment target iOS 17.0 のアプリは、push-to-start (17.2) 以外すべて素で使える。**
ActivityKit の一部新 overload (style / scheduling 付き) は iOS 18.0+ (SDK 実測)。

### HIG の設計意図 (面の選び分け)

- **Live Activity** = 「keep track of tasks and events in glanceable locations」だが
  **"delivering frequent content and status updates over a few hours"** — **数時間の有界な進行中タスク**が対象
  (配達の残り時間・試合中のスコア・ワークアウト中の指標)。**終日ずっと出す常設表示ではない**
- **Widget** = 「timely, glanceable content」— 常設・低頻度更新の一瞥表示はこちら
- Live Activity は 1 実装で Lock Screen / Dynamic Island / StandBy / Watch Smart Stack / CarPlay に展開される
  (compact / minimal / expanded の3プレゼンテーション全対応が**必須**)

## Why

- 「次の予定を一瞥」系の要望に Live Activity を当てると HIG の想定 (数時間の有界タスク) から外れる。
  **常時ある「次の◯◯」はウィジェットが正解**、Live Activity は「今まさに進行中の 1 コマ」に限れば筋が通る
- インタラクティブ ウィジェット (`Button(intent:)`) が iOS 17.0 なので、
  **iOS 17 ターゲットならウィジェットから直接ワンタップ記録が作れる** (アプリを開かせない)。
  Penmark も同じ手を打っている (App Store 記載: iOS 17 以降はウィジェットから出席登録可)
- Live Activity の3プレゼンテーション必須は実装コストの主因。「Dynamic Island だけ」は選べない

## How to apply

1. **常設の「次の◯◯」→ WidgetKit** (`systemSmall` + `accessoryRectangular`)。iOS 17 なら `Button(intent:)` で操作まで載せる
2. **進行中の 1 タスク (数時間) → ActivityKit**。3プレゼンテーション全部デザインする覚悟がある時だけ
3. availability を疑ったら **docs JSON の `metadata.platforms` を引く**。記憶で書かない
4. `UIScreen.main` は **iOS 26 で deprecated**。新規コードでは `GeometryReader` /
   `UIWindowScene.keyWindow` 経由に寄せる。既存コードの棚卸し対象

## 反例 / 限界

- 「Live Activity は最大◯時間で消える」等の**具体的な時間上限は本調査で一次ソース未確認**。
  HIG は "a few hours" としか言っていない。ActivityKit の実運用上限を設計に織り込むなら別途確認が必要
- 上記は 2026-07-17 の実測。HIG / availability は年次で動くので、設計doc に書く前に docs JSON で再確認する
