---
title: 日本向け場所検索 autocomplete API の選定事情 (2026-08)
category: library
project: omatase
tags: [geocoding, autocomplete, photon, nominatim, google-places, mapbox, locationiq, map]
created: 2026-08-06
sources:
  - https://operations.osmfoundation.org/policies/nominatim/
  - https://github.com/komoot/photon
  - https://github.com/komoot/photon/blob/master/docs/api-v1.md
  - https://docs.mapbox.com/api/search/search-box/
  - https://developers.google.com/maps/documentation/places/web-service/policies
  - https://stadiamaps.com/pricing/
  - https://locationiq.com/pricing
  - https://developer.yahoo.co.jp/webapi/map/faq.html
model-era: opus-5
---

## Context

omatase の場所選択モーダルに「入力ごとに予測が出る検索 (autocomplete)」を足すための API 選定 (2026-08 実測)。要件: 日本語品質 / 結果が範囲 (bbox) か地点かを区別 / MapLibre + react-native-maps という**非ベンダー地図への表示が規約上許されること** / 無料〜低コスト。

## What

- **Nominatim 公開インスタンスは autocomplete 明示禁止**。「Auto-complete search is not yet supported by Nominatim and you must not implement such a service on the client side using the API」(公式 Usage Policy)。debounce を付けてもキー入力駆動の検索は不可
- **Google Places / Mapbox Search Box は「自社地図ロック」規約**。Google: 「Places API results must display on a Google Map, if a map is used」。Mapbox: suggestion の表示は Mapbox map services 必須 (Google Maps / MapKit JS への表示は例として明示 NG)。MapLibre + OSM タイルや react-native-maps (Apple 地図) との併用は規約違反
- **Photon (photon.komoot.io) が無料・キー不要・autocomplete 設計** (search-as-you-type が公式ユースケース)。実測 (2026-08-06):
  - 「東京」→ 東京駅 (railway/station, 点) + **東京都 (place/province, `extent` bbox 付き)** + 東京ドーム + 羽田 — 範囲/地点の振り分けに必要な材料が揃う
  - 「新宿」+ lat/lon bias → 新宿駅群が上位。「スターバックス 渋谷」も的中
  - `lang=ja` は**非対応** (default/de/en/fr のみ) だが `lang` 省略 (default) で OSM の現地語名 = 日本語が返る
  - CORS は `Access-Control-Allow-Origin: *` (client 直叩き可能だが proxy 推奨)
  - 規約は「reasonable limit」のみ。保証なし・過剰利用は ban。目安 1 req/s (R package の default)
  - 注意: `extent` は建物 POI (東京ドーム等) にも付く。**範囲/地点の判定は extent の有無でなく osm_key/type で行う**。また東京都の extent は小笠原を含み巨大 ([135.85,35.90,154.21,20.21])
- **GSI (国土地理院) AddressSearch は autocomplete 品質 NG** (実測: 「東京駅」で「北海道札幌市東区」等の部分一致 53 件、東京駅は中位に埋没。type/bbox なし)。CORS * で無料だが仕様変更・継続性は無保証
- **YOLP (Yahoo) は 2026-08 現在存続** (2020 の一部終了以降の廃止告知なし)。無料 5 万アクセス/日。ただし autocomplete 専用 endpoint はなく、他社地図への表示可否は FAQ に記載なし (未確定)
- **ホスティング型 OSM 系の保険**: LocationIQ (free 5,000 req/day、autocomplete あり、リンク表記で商用可) / Stadia Maps (Pelias 系、free 200,000 credits/月・autocomplete 1 credit/req だが **free tier は商用不可**)
- Apple 系 (MKLocalSearchCompleter / Maps Server API 25,000 calls/day) は iOS ネイティブでは強力だが、Expo は custom native module が要り、web は MapKit JS (Apple 地図前提) になるため web=MapLibre 構成と両立しない

## How to apply

- 非ベンダー地図 (MapLibre/OSM) に検索結果を出す構成では、Google/Mapbox は最初から候補から外す (規約で詰む)
- 無料で autocomplete をやるなら Photon を Go 等の backend proxy 経由で (User-Agent 統一 + キャッシュ + rate 制御)。公開インスタンス依存のリスクは LocationIQ (API 互換ではないが同じ proxy 裏で差し替え可能) か自前ホスト (planet 約95GB、日本抽出なら小さい) でヘッジ
- 範囲→fitBounds / 地点→pin の振り分けは `osm_key in {place, boundary}` かつ `type in {city, district, county, state, country}` を「範囲」、それ以外を「地点」とする。bbox は extent を使うが、都道府県は離島で bbox が暴れるため zoom 下限を設ける
