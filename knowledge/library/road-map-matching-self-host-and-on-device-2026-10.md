---
title: 道路 map matching の選択肢 (OSRM / Valhalla / GraphHopper / valhalla-mobile) と Japan での実測 (2026-10)
category: library
project: global
tags: [map-matching, valhalla, osrm, graphhopper, valhalla-mobile, openfreemap, osm, japan, gps]
created: 2026-10-19
sources:
  - https://github.com/Project-OSRM/osrm-backend/wiki/Disk-and-Memory-Requirements
  - https://raw.githubusercontent.com/Project-OSRM/osrm-backend/master/src/tools/routed.cpp
  - https://raw.githubusercontent.com/valhalla/valhalla/master/docs/docs/api/map-matching.md
  - https://raw.githubusercontent.com/valhalla/valhalla/master/scripts/valhalla_build_config
  - https://raw.githubusercontent.com/graphhopper/graphhopper/master/map-matching/README.md
  - https://raw.githubusercontent.com/graphhopper/graphhopper/master/docs/core/deploy.md
  - https://github.com/Rallista/valhalla-mobile
  - https://openfreemap.org/tos/
---

## Context
Bloom の行動線補正の調査 (2026-10-19)。道路に吸着する手段の事実だけ残す。

## What
- **OSRM** (BSD-2、v26.10.0 / 2026-10-01 = 暦版): `/match` は `timestamps` `radiuses` (= GPS 精度の標準偏差) `gaps=split|ignore` `tidy`。osrm-routed の `--max-matching-size` 既定 **100 点**。公式 wiki の RAM 実測は planet (pbf 61 GiB, v5.26, 2021) で car ~123 GiB、"scale roughly linear"。日本の実測は無い。
- **Valhalla** (MIT、3.9.1 / 2026-10-06): `trace_route` / `trace_attributes`、`shape` に `{lat,lon,time}`、`trace_options.{gps_accuracy,search_radius(最大100m),turn_penalty_factor}`、`shape_match=map_snap`。config 既定 `service_limits.trace`: max_shape **16000 点**、max_distance 200 km。
- **GraphHopper** (Apache-2.0、11.1 / 2026-09-29): `map-matching/` モジュール、`POST /match?profile=car` に GPX。import は planet で ~60 GB RAM (docs 記載)、CH 準備は別途。Newson-Krumm HMM。
- **valhalla-mobile** (Rallista、MIT、0.6.4 / 2026-10-06): iOS (SwiftPM) / Android に Valhalla を静的 lib 化。`trace_route` / `trace_attributes` を**端末のタイルだけで**実行可 (server 不要)。Flutter 用 plugin は無い (自前 MethodChannel)。
- **実測 (2026-10-19、M 系 Mac / Docker VM 3.8 GiB)**: Geofabrik Kanto 520 MB → 東京 bbox (139.55-139.92E, 35.53-35.82N) 121 MB pbf (道路 1.41M node / 395k way) → Valhalla 3.9 `valhalla_build_tiles` **81 秒、ピーク RSS 1.1 GiB、tiles 153 MiB (tgz 52 MiB)**。同 tiles で trace_route 成功。Kanto 全体の道路は highway=* 全部で 12.3M node / 2.44M way (pbf 144 MB)、自動車道+service 8.2M node、primary〜tertiary+trunk+motorway 1.83M node / 187k way (pbf 27 MB)。
- **OpenFreeMap** (OpenMapTiles schema、maxzoom 14): `transportation` レイヤに道路線形 (class/subclass/brunnel/oneway)。ToS: オフライン DL は 1 回 3000 tile か 50 MB・並列 4・固有 User-Agent まで、それ以外の自動収集は禁止、超過は info@openfreemap.org へ。z14 の東京 tile は全レイヤで 745 KB (gz 前後は未確認)。
- 日本向け OSM 実測 (Valhalla/OSRM/GH の全国 RAM) は一次情報が見つからず未確認。

## Why
「サーバーで道路補正」「端末で道路補正」はどちらも既製品がある。差は (1) 日本のデータ量 (2) 軌跡を端末外へ出すか。

## How to apply
- 全国分の RAM/ディスクは関東分の実測から外挿し、必ず Touri のサーバーで再測する (東京 bbox は道路密度が最大級で、線形外挿は安全側)。
- 軌跡を平文で送る方式は E2E の約束 (privacy.html) と衝突する。端末完結なら valhalla-mobile + 地域 tiles ダウンロードが筋。
