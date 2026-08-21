---
title: Flutter で iOS バックグラウンド位置 (visits / significant change / Always 許可 / 日次バッチ) を扱う時の現状 (2026-08)
category: library
project: global
tags: [flutter, ios, core-location, clvisit, significant-location-change, always-authorization, workmanager, bgtaskscheduler, maplibre]
created: 2026-08-19
sources:
  - https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoringvisits()
  - https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoringsignificantlocationchanges()
  - https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services
  - https://developer.apple.com/documentation/corelocation/cllocationmanager/requestalwaysauthorization()
  - https://developer.apple.com/documentation/corelocation/cllocationmanager/showsbackgroundlocationindicator
  - https://support.apple.com/en-us/102515
  - https://github.com/fluttercommunity/flutter_workmanager/blob/main/docs/customization.mdx
  - https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate
  - https://pub.dev/packages/flutter_background_geolocation
  - https://github.com/ExpTechTW/DPIP/blob/main/ios/Runner/BackgroundLocationPlugin.swift
---

## Context

Bloom. (位置ヒートマップ SNS、旧 slug itsumo) の Phase-0 事前調査で、Flutter × iOS の低電力バックグラウンド位置取得と日次バッチの成立性を一次資料 + pub.dev 実測で確認した (2026-08-19)。PJ 固有の結論は `projects/bloom/.knowledge/research-flutter-location-map.md`。ここは他 PJ でも使う一般部分。

## What

- **CLVisit (`startMonitoringVisits`) を Dart API として公開している pub.dev プラグインは無い** (2026-08-19 時点。`flutter_background_geolocation` 5.5.0 / `locus` 2.4.0 / `background_geo_tracker` 0.5.0 / `geolocator` 14.0.3 のソース grep で該当なし。GitHub code search でも Flutter 系は DPIP のアプリ内 Swift のみ)。visits が要るなら **Runner に Swift の MethodChannel/EventChannel を置く**のが前例に沿った最短。
- significant location change (SLC) は `flutter_background_geolocation` (`useSignificantChangesOnly`)、`locus`、`background_geo_tracker` が対応。transistorsoft は **iOS は無償** (ライセンス必須は Android RELEASE のみ、DEBUG は全機能無償)。
- Apple の確定仕様:
  - SLC: 500m 移動 / 5 分以上の間隔。terminated 後も relaunch (launchOptions に `location`)。**relaunch 後は再度 start が必要**
  - visits: terminated 後も relaunch。**relaunch 後は manager + delegate を作るだけで再開** (再 start 不要)。Precise 未許可なら reduced accuracy で来る
  - terminated アプリを起こせるのは **Always かつ SLC / visits / region monitoring のみ**。When in Use は起こさない
  - Always は 2 段: WhenInUse → `requestAlwaysAuthorization()` は **1 回しか効かない**。notDetermined から直接呼ぶと 1 回目は WhenInUse 文言 = Provisional Always、2 回目の OS プロンプトは「Always が要るイベント配信時、典型的にはアプリ非起動中」に出る。「Allow Once」を選ばれると以後の Always 要求は無視
  - Info.plist: `NSLocationWhenInUseUsageDescription` + `NSLocationAlwaysAndWhenInUseUsageDescription`。欠落で要求は即失敗
  - `showsBackgroundLocationIndicator` (default false) を true にすると Always アプリの BG 使用時に青バー/ピル。When in Use アプリは強制表示。iOS 16+ は Control Center にもインジケータ
  - OS は BG 位置利用アプリについて**地図付きの定期リマインダー**を出し「continue to allow?」を聞く (ユーザーは地図表示だけ OFF 可、アラート自体は消せない)
- **iOS で「毎日 X 時に端末バッチ」は不可能**: workmanager 0.10.7 の公式 docs が「frequency は iOS では無視、earliestBeginDate はヒント、hours 遅延や skip を想定せよ、swipe kill 後は再起動まで一切走らない」と明記。Apple も `earliestBeginDate` は「それより早く始まらない」保証のみ。→ 定時処理はサーバー側に置き、端末は「起動/前景/位置イベントで随時送信」にする。
- 地図: `maplibre_gl` 0.26.2 (iOS 13+) は `addGeoJsonSource` + `addFillLayer` / `addHeatmapLayer` を持ち、OpenFreeMap (`tiles.openfreemap.org/styles/{liberty,bright,positron,dark,fiord}`) は API key 不要・無制限。`flutter_map_heatmap` 0.0.8 は `flutter_map <8` 固定で 8.x と組めない。

## Why

Flutter の位置プラグインは「連続追跡」需要で発達しており、iOS 固有の低電力 API (visits) はラップされていない。BG タスクの時刻保証が無いのは iOS の BGTaskScheduler 設計そのもので、プラグインの問題ではない。

## How to apply

- 低電力 BG 位置が要る Flutter iOS 設計は「Runner 内 Swift (visits + SLC) → 端末 DB → 前景/イベント時に送信」を既定形にする。Dart だけで閉じようとしない。
- 許可 UX は「WhenInUse で価値を見せる → 説明画面 → Always 要求 (1 回きり)」+ OS リマインダーの予告をオンボーディングに含める。
- 「毎日 21 時」等の定時反映は必ずサーバー側の公開時刻として設計する。
- 再確認手順: `curl -s https://pub.dev/api/packages/<pkg>` で latest/published、Apple は `developer.apple.com/tutorials/data/documentation/corelocation/<path>.json`。
