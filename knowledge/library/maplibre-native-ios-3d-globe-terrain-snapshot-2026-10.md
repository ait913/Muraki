---
title: "maplibre_gl 0.26 / maplibre-native iOS の 3D 能力 (globe・terrain は未出荷、takeSnapshot は実行時レイヤを落とす)"
category: library
project: bloom
tags: [maplibre_gl, maplibre-native, ios, globe, terrain, fill-extrusion, snapshot, openfreemap]
created: 2026-10-11
sources:
  - "~/.pub-cache/hosted/pub.dev/maplibre_gl-0.26.2/ios/maplibre_gl/Sources/maplibre_gl/MapLibreMapController.swift:1287-1340 (takeSnapshot), :442-467 (animateCamera -> mapView.fly)"
  - "~/.pub-cache/hosted/pub.dev/maplibre_gl-0.26.2/ios/maplibre_gl.podspec:19 (MapLibre 6.27.0 固定)"
  - "gh api repos/maplibre/maplibre-native/releases (ios-v6.31.0 最新安定 / ios-v7.0.0-pre-globe.0 は CocoaPods 非公開)"
  - "maplibre-native PR #4533 (globe, open) / #4190 (Terrain 3D, open) / #4534 (sky, open) — 2026-10-11 時点"
  - "https://tiles.openfreemap.org/styles/liberty , /planet (TileJSON)"
---

## What

- Dart API (0.26.2) に **terrain / sky / projection(globe) / setLight は無い**。あるのは fill-extrusion・heatmap・hillshade・line-gradient(lineMetrics)・line-blur・RasterDem source と `CameraPosition.tilt/bearing`・`CameraUpdate.tiltTo`。
- maplibre-native の globe (#4533)・terrain (#4190)・sky (#4534) は 2026-10-11 時点 **すべて open PR**。iOS の安定版に無い。7.0.0-pre-globe.0 は Bazel ローカルビルドの XCFramework で CocoaPods に出ていない。
- **iOS の `takeSnapshot` は `mapView.styleURL` から新しく MLNMapSnapshotter を作る**ので、`addGeoJsonSource`/`addFillLayer` 等で実行時に足したレイヤは写らない (camera と zoom だけ引き継ぐ)。
- `animateCamera` は iOS で `mapView.fly(to:)` (flyTo 曲線: 引いて寄る)。tilt/bearing も同じ camera に入る。
- OpenFreeMap の tile `building` は `render_height` / `render_min_height` を持つ。`styles/dark` は `building` を **fill (平面)** にしており `building-3d` が無い。`styles/liberty` は `building-3d` (fill-extrusion, minzoom 14) を持つ。両 style とも terrain/sky/projection キー無し、DEM ソース無し。

## How to apply

- 3D は「fill-extrusion 建物 + tilt カメラ」まで。terrain / globe を設計の前提にしない。
- 地図を動画にするなら、plugin の takeSnapshot でなく Swift bridge で MLNMapSnapshotter を直接使い、delegate の style 読み込み後フックでレイヤを足す。
