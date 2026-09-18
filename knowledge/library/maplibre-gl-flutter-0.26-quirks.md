---
title: "maplibre_gl 0.26.2 (Flutter) の実装上の癖 — addImage の scale / featureTaps / GeoJSON 送信コスト"
category: library
project: bloom
tags: [flutter, maplibre_gl, ios, addImage, featureTapsTriggersMapClick, geojson, performance]
created: 2026-09-18
sources:
  - "Codex 設計レビュー + Architect の一次ソース確認 (sessions/2026-09-18-feed33c7)"
  - "~/.pub-cache/hosted/pub.dev/maplibre_gl-0.26.2/ios/maplibre_gl/Sources/maplibre_gl/MapLibreMapController.swift:892, :1423"
  - "~/.pub-cache/hosted/pub.dev/maplibre_gl-0.26.2/lib/src/maplibre_map.dart:31, controller.dart:620, layer_properties.dart:1134"
  - "~/.pub-cache/hosted/pub.dev/maplibre_gl_platform_interface-0.26.2/lib/src/method_channel_maplibre_gl.dart:757"
---

## Context

Bloom M2 (地図 UI 刷新) で、Flutter canvas でラスタライズした画像を symbol layer に載せる / ピンのタップを拾う / 数千セルの GeoJSON を送る、の 3 つで設計前提が実ソースと食い違った。全部 Codex の設計レビューで検出され、Architect が pub cache のソースで確認した事実。

## What

1. **iOS の `addImage` は `UIImage(data:, scale: UIScreen.main.scale)` で登録する** (`MapLibreMapController.swift:892`)。dpr 倍で描いた PNG はそのまま pt 寸法になるので、`iconSize: 1/dpr` を掛けると二重縮小 (3x で 40pt → 13pt)。**dpr 倍ラスタライズ + `iconSize: 1`** が正しい。`iconOffset` も pt 値そのまま。Android は `inScaled=false` の生 px 登録 (`MapLibreMapController.java:1647`) で倍率が違う → プラットフォーム分岐が要る。
2. **`featureTapsTriggersMapClick` の既定は false** (`maplibre_map.dart:31`)。symbol/circle/fill layer は `enableInteraction` 既定 true (`controller.dart:620`) で、iOS 実装はフィーチャー検出時に map click を抑止する (`.swift:1423`)。つまり **interaction 有効な layer の上では `onMapClick` が発火しない**。装飾 layer は `enableInteraction: false`、タップを拾う layer だけ interactive にして `onFeatureTapped` で受けるか、`featureTapsTriggersMapClick: true` を指定する。Bloom では `heat-fill` が既定 true のままで、その上の候補セルタップ (`onMapClick`) が死んでいた疑いがある。
3. **circle の `circleStrokeWidth` は `circleRadius` の外側に付く** (`layer_properties.dart:1134`)。白縁込みの外径 14pt なら radius 5 + stroke 2。
4. **`setGeoJsonSource` / `addGeoJsonSource` は呼び出し側 (UI isolate) で同期 `jsonEncode` する** (`method_channel_maplibre_gl.dart:757`)。platform_interface 0.27.0 には大容量 payload の `compute` 退避と source 毎の直列化があるが、**lock が 0.26.2 のままなら効かない**。10Hz で数千点を再送する設計は、描画用点列の間引き (Bloom は ≤ 1,500 点) と「送信中は最新フレームだけ保持」の集約が必要。
5. `FillLayerProperties` に `fillSortKey` が無い → メンバー毎の重ね順は layer を分けて固定する。

## Why

設計 doc は「MapLibre GL JS の常識」で書きがちだが、Flutter バインディングは iOS/Android で画像登録の倍率もタップ配送も違う。pub cache のソースを読めば 5 分で分かる事実なので、設計前リサーチで **`addImage` の scale と `featureTapsTriggersMapClick` は必ず確認項目に入れる**。

## How to apply

- 画像 symbol: dpr 倍で描く → `addImage(name, png)` → `iconSize: 1`。実機で 3x 端末の実寸を測る (Bloom §10 #8)
- タップ: 装飾 layer は全部 `enableInteraction: false`。拾いたい layer だけ interactive + `onFeatureTapped`。既存 layer を足した時は「その上の `onMapClick` が死なないか」を確認
- GeoJSON: `pubspec.lock` の `maplibre_gl_platform_interface` の版を見てから送信量を設計する
