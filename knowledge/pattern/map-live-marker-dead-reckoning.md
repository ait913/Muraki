---
title: 地図の現在地マーカーを滑らかに動かす — 1 Hz fix + Doppler 速度で先読み、20 Hz 送信、表示側ヒステリシス、自前フラグのソフト追従
category: pattern
project: global
tags: [maplibre_gl, corelocation, dead-reckoning, current-location, camera-follow, h3, flutter]
created: 2026-09-19
sources:
  - "bloom M3 設計 doc: projects/bloom/.designs/20260918-live-movement-m3.md"
  - "projects/bloom/mocks/m3-live/SPEC.md (モック抽出値)"
  - "projects/bloom/.knowledge/research-m3-live-movement.md"
---

## Context

位置情報アプリの地図で「自分の位置がカクカク飛ぶ」「移動しても塗りが追いつかない」「カメラが自分を見失う」を同時に直す設計 (bloom M3、Flutter 3.47 + maplibre_gl 0.26.2 + iOS CoreLocation)。モックは MapLibre GL JS の 60 fps 前提で書かれていて、Flutter の MethodChannel バインディングにそのまま持ち込めない。

## What

1. **fix 供給**: 現在地専用の別 `CLLocationManager` を作らず、既存の連続測位の「作動理由 (reason)」集合に `mapView` を足す。`desiredAccuracy = Best`、**`distanceFilter = none`** (1 Hz 配送)。`distanceFilter` を数 m にすると静止中に fix が止まり、dead reckoning が最後の速度で走り続ける。GPS の電池は `startUpdatingLocation` している時間で決まり、`distanceFilter` は節約にならない。前景 × 画面表示中だけ積み、`applicationDidEnterBackground` で Swift 側からも外す (Dart が固まっても GPS が残らない)
2. **記録側の不変条件**: 同じ manager を共有すると記録用の `distanceFilter` (10 m) が live 用に負けるので、記録処理にソフトウェア距離フィルタ (直前の記録点から 10 m 未満は捨てる) を足して密度を保つ
3. **速度ベクトル**: 3 fix 差分 (モック) より **`CLLocation.speed` / `course` (Doppler)** を優先する。1 Hz・水平誤差 12 m の fix を 2 s で差分すると誤差 ≈ 8.5 m/s で歩行速度が埋もれる。`speed < 0.5` は v = 0、`course < 0` (無効) の時だけ差分にフォールバック (dt ≥ 2 s の窓)
4. **先読みに上限を置く** (3 s): モックは上限なしだが、fix 途絶 (地下・屋内) でマーカーが建物の中へ歩いていく
5. **送信は 20 Hz 上限 + 送信中は最新 1 件だけ保持**、Dart 側は `Ticker` で純関数を回し、静止して補正・回頭が終わったら Ticker を止める。数値根拠: zoom 18 でも歩行 1.3 m/s は 50 ms あたり 0.27 pt
6. **精度ハロー (m 単位) は zoom 指数補間で 1 回送ればよい**: `circle-radius: ['interpolate', ['exponential', 2], ['zoom'], 0, r0, 22, r0·2^22]` は `r0·2^z` に厳密一致 (t = (2^z − 1)/(2^22 − 1))。`r0 = acc × 512 / (40075016.686 × cos lat)` (MapLibre の world は 512 × 2^z px)
7. **進行方向コーンは画像 symbol** (`iconRotate` + `iconRotationAlignment: 'map'` + `iconAnchor: 'bottom'`、dpr 倍ラスタライズ + `iconSize 1`)。fill Polygon だと zoom ごとに geo 半径の再生成が要る。コンパス (`CLHeading`) は端末の向きであって進行方向でないので使わない
8. **セル塗りのヒステリシス (境界から N m 内側) は表示側で、DB は真実のまま**: 生 fix はセル境界で即 DB に書く。表示は「描画位置の近傍 (同一 / 隣接) に新しく増えたセルは、描画位置が N m 内側に入るまでブロブに合流させない (保留)」+「描画位置が先に確定して DB が無ければ暫定表示 (記録中の時だけ)」。DB を迂回して塗ると記録停止中に「塗れたように見えて残らない」嘘になる
9. **ソフト追従で gesture / programmatic を区別するコールバックが無い時**: `animateCamera` 直後 (duration + 150 ms) の `onCameraMove` を無視し、それ以外は全てユーザー操作として N 秒停止。マーカーの画面座標は `toScreenLocation` (MethodChannel 往復) でなく `cameraPosition` から Web Mercator の閉形式 (`screen = size/2 + R(−bearing)·(world(target) − world(center))`、pitch 0 前提)
10. **「表示中だけ」の供給源**: go_router の `StatefulShellRoute.indexedStack` はタブ画面を mount し続けるので、`initState` / `dispose` は可視性でない。shell の `currentIndex` を provider に写して駆動する

## Why

- Flutter の MapLibre は GeoJSON 差し替えが MethodChannel 往復 (同期 `jsonEncode`) で、GL JS の `setData` 毎フレームとはコストの桁が違う (`library/maplibre-gl-flutter-0.26-quirks.md` #4)
- CoreLocation は Doppler 由来の速度・進行方向を持っていて、位置差分より桁で精度が良い。モックにはその入力が無かっただけ
- 「即時塗り」を DB の外で作ると、共有側 (集計・公開) の規律と表示が食い違う経路が生まれる

## How to apply

- 現在地マーカー系の設計では、まず既存の位置供給 (reason 集合・記録側のフィルタ) を grep し、**同一 manager に理由を足す**形で書く。別インスタンスは優先順位表の外に GPS を作る
- payload に `speed` / `course` / `speedAccuracy` / `courseAccuracy` / `horizontalAccuracy` を最初から載せる (負 = 無効の CLLocation 規約をそのまま通し、Dart で null に)
- Reviewer 用の数値 (先読み位置・画面座標・ハロー px・境界距離) はスクリプトで実走して書く。境界距離は合成の正方形 ring で閾値、実 H3 セルはサニティ (±0.1 m)
- 「表示中だけ GPS」は、Swift 側のライフサイクルフックにもバックストップを置く
