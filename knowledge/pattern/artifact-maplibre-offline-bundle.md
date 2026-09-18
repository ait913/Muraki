---
title: "claude.ai Artifact で MapLibre の実タイル地図を動かす — タイル/グリフを base64 JSON に包んで addProtocol で復号"
category: pattern
project: global
tags: [artifact, csp, maplibre-gl-js, openfreemap, addProtocol, mock, h3]
created: 2026-09-18
sources:
  - "Muraki/projects/bloom/mocks/m2/build-artifact.py (実装)"
  - "sessions/2026-09-18-feed33c7"
---

## Context

地図 UI のモックを Artifact (claude.ai) で共有したい。Artifact の CSP は **外部 script は cdnjs / jsdelivr(npm) のみ、stylesheet は Google Fonts のみ、fetch/XHR/画像/バイナリは他ホスト全部遮断**。さらに同梱ファイル (`files`) は「標準 web media type」だけ配信され、`application/x-protobuf` (MVT タイル・グリフ PBF) は **publish 自体が拒否される**。

## What

`mocks/m2/build-artifact.py` の変換パイプライン:

1. 対象範囲 (bbox × zoom 12〜14、OpenFreeMap planet は maxzoom 14) のタイル・スプライト・Latin グリフ 3 レンジを取得
2. **バイナリは `{"b64": "..."}` の JSON に包む** (JSON は配信可)。ページ側で `maplibregl.addProtocol("bundle", async ({url}) => { const j = await (await fetch(url.replace("bundle://","").replace(/\.pbf$/,"") + ".json")).json(); return { data: base64→ArrayBuffer }; })` を map 生成前に登録し、style の `tiles` / `glyphs` を `bundle://tiles/{z}/{x}/{y}.pbf` / `bundle://glyphs/{fontstack}/{range}.pbf` にする
3. style JSON はローカル参照に書換 (低ズーム用 raster source は削除、`sprite` は `sprites/ofm`)。フォント名の空白は公開パスに持ち込まず `NotoSansRegular` に付け替え (style の `text-font` も同名に)
4. maplibre-gl の CSS はインライン化。外殻タグ (`<!DOCTYPE>/<html>/<head>/<body>`) は Artifact 側スケルトンが付けるので剥がす — **`</?head[^>]*>` で `<header>` を巻き込む事故**に注意 (`(?=[\s>])` で区切る)
5. `maxBounds` / `minZoom` で同梱範囲外にカメラを出さない。資産 404 (範囲外・非同梱グリフ) は map の `error` ハンドラで握りつぶし、UI の fail 表示にしない
6. ラベルは `name:latin` (CJK グリフは 1 レンジ ≈ 190KB × 82 レンジ × 書体数で断念)

規模: 渋谷 7km 四方で 44 ファイル / 16MB (base64 で 1.3 倍)。1 テキストファイル 16MB・1 版 64MB・255 エントリの上限内。

## Why

同梱化しないと Artifact 上で地図が真っ黒になる (fetch 遮断はエラーも出ない)。base64 JSON + addProtocol は MapLibre 側の変更なしで済み、正本の HTML は触らず変換スクリプトで dist を作れるので、Codex にモックを直させた後も再ビルド → 同 URL に publish で更新できる。

## How to apply

- `python3 mocks/m2/build-artifact.py` → `Artifact publish` (root = dist、files = files.json の一覧、contentType 指定不要)。更新は同じ file_path で再 publish
- ローカル確認は `python3 -m http.server` で (file:// は MapLibre が弾く)
- headless Chrome の `captureScreenshot` が返らない日は構造検証 (`window.__m2` フックで `map.getStyle()` / sources / DOM) に切替える — [[tool-quirk/chrome-for-testing]]
