---
title: 鉄道への map matching / 国土数値情報 N02 / 場所を明かさない接近判定 / video_player の差し込み口 (2026-10 時点の実測)
category: library
project: global
tags: [map-matching, valhalla, osrm, openrailrouting, n02, h3, hmac, proximity, notification-service-extension, video_player, maplibre_gl]
created: 2026-10-15
sources:
  - https://raw.githubusercontent.com/valhalla/valhalla/master/lua/graph.lua
  - https://github.com/geofabrik/OpenRailRouting
  - https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2024.html
  - https://nlftp.mlit.go.jp/ksj/gml/data/N02/N02-24/N02-24_GML.zip
  - https://www.ndss-symposium.org/wp-content/uploads/2017/09/nara.pdf
  - https://developer.apple.com/tutorials/data/documentation/usernotifications/modifying-content-in-newly-delivered-notifications.json
  - https://developer.apple.com/tutorials/data/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions.json
  - https://pub.dev/api/archives/video_player_avfoundation-2.12.1.tar.gz
  - https://raw.githubusercontent.com/maplibre/flutter-maplibre-gl/main/CHANGELOG.md
---

## Context
Bloom の軌跡補正 / 移動手段判別 / 接近判定の設計前調査 (2026-10-15)。他 PJ でも使う事実だけ残す。

## What
- **Valhalla は線路を道路グラフに取り込まない**: `lua/graph.lua` は `highway` / ferry / `route=shuttle_train` (カートレイン) だけを辿り、`railway=rail` の通常線路は入らない (railway は shuttle の rc 付与でのみ登場)。Meili は電車に map match できない。ライセンス MIT、3.9.1 (2026-10-06)。
- **鉄道に合わせられる既製品は OpenRailRouting** (Geofabrik、GraphHopper fork、Apache-2.0、v1.2 / 2026-09-30、map matching / isochrone 対応、`railway=rail/light_rail/tram/subway` を custom model で選択)。OSRM は公式に鉄道 profile 無し (メンテナ「鉄道向きでない」、古い community lua のみ)。
- **OSM japan-latest.osm.pbf = 2.4 GB** (Geofabrik 2026-10-13)。OSRM wiki の planet 実測 (pbf 61GB に対し car で RAM ~123GiB) の比例外挿で Japan car ≈ 5GiB 前後 (外挿、日本実測は未確認)。鉄道のみに osmium で絞れば桁違いに小さい (未実測)。
- **国土数値情報 N02 (鉄道)**: 2025 年度版が最新、2024 版 zip 12.7MB (GML / Shape / GeoJSON 同梱、JGD2011)。RailroadSection.geojson 14.3MB = 21,932 LineString / 404,605 頂点 / 頂点間隔 中央値 47m・p99 400m (実測、直線近似が粗い区間あり)。属性は鉄道区分 N02_001 / 事業者種別 N02_002 / 路線名 N02_003 / 運営会社 N02_004 のみ。**2020 年以降は CC BY 4.0 (商用可・出典必須)**、加工時は「加工した」旨の表示 (利用規約 https://nlftp.mlit.go.jp/ksj/other/agreement.html)。
- **近接テストの古典 (Narayanan+ NDSS 2011)**: グリッドのセル境界問題は「3 枚のオフセットした六角格子を重ねる」で解く。鍵を知らない者は 34bit 程度の位置空間を総当たりできる点が脅威モデルの核 → 鍵なしハッシュは無意味、共有鍵必須。サーバー仲介型は効率が良いがサーバー共謀に弱い。
- **Notification Service Extension**: alert 通知 + `mutable-content: 1` のとき端末上で暗号文を復号して文面を書き換えられる (Apple 公式「Decrypt data sent in an encrypted format」を用途に明記)。処理は約 30 秒、超過時は元の通知がそのまま出る。silent push では動かない。
- **iOS 領域監視は 1 アプリ 20 件まで** (全種類合計)。再起動後は端末ロック解除が要る。起動されたら同じ identifier で再登録。
- **video_player_avfoundation 2.12.1 (video_player 2.14.1) に AVAssetResourceLoader の差し込み口は無い**: AVURLAsset は URL + `AVURLAssetHTTPHeaderFieldsKey` だけで生成 (`VideoPlayerPlugin.swift:275`)。カスタム scheme での復号再生は video_player のままでは不可。
- **maplibre_gl 0.27.1 (2026-09-10)**: 0.26.2 比で大容量 GeoJSON のエンコードをバックグラウンド化 (#366)、iOS の `EXC_BAD_ACCESS` (0.26.2 の custom headers 由来) 修正 (#1009)、`ManualLocationSource`、iOS の feature state は未対応 (throw)。`iconOverlap` / `textOverlap` / `textVariableAnchorOffset` の一部は web のみ。MapLibre style spec で `icon-size` は layout 扱い (transition 不可)、`icon-opacity` / `circle-radius` / `icon-translate` は paint (transition 可)。
- **Dart 側**: `h3_core` 1.0.6 (2026-05-27、Apache-2.0、H3 4.4.1、`cellsToMultiPolygon` あり、FFI + web は h3-js)。`h3_flutter` 0.7.1 (2025-12-11、H3 4.2.1) は旧系統。Go: `uber/h3-go/v4` v4.5.0 (2026-05-26) に `CellsToMultiPolygon`。stay point / Kalman / Douglas-Peucker の定番 Dart パッケージは無い (2019〜2024 止まりの小物のみ) → 自前が現実的。

## Why
「Valhalla で電車にスナップ」「video_player に復号 scheme を足す」は設計に書きがちだが、どちらも実ソースで不可。先に潰す。

## How to apply
鉄道補正は (a) N02 or OSM 鉄道を端末同梱して Dart で最近傍スナップ、(b) サーバーに OpenRailRouting。Valhalla/OSRM を前提にしない。暗号化動画の再生は「一時ファイル」か「loopback HTTP + Range」か独自 plugin のどれか。
