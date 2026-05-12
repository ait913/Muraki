---
title: "Leaflet マップを使う画面で modal/overlay は z-index 1000 超え必須"
category: gotcha
project: global
tags: [leaflet, react-leaflet, z-index, modal, tailwind]
created: 2026-05-10
sources:
  - https://leafletjs.com/reference.html#map-pane
  - https://github.com/Leaflet/Leaflet/blob/main/dist/leaflet.css
---

## Context
React アプリで Leaflet (react-leaflet) の地図と同一スクリーン内に modal / overlay を出した時、Tailwind の `z-20` や `z-50` 程度だと **modal が地図の Zoom コントロールや属性表示の下に潜る**。

## What
Leaflet の z-index は `leaflet.css` で固定定義されており、Tailwind の標準スケールより遥かに大きい:

| 要素 | z-index |
|---|---|
| map pane | 1 |
| tile pane | 200 |
| overlay pane | 400 |
| shadow pane | 500 |
| marker pane | 600 |
| tooltip pane | 650 |
| popup pane | 700 |
| **map controls (zoom, attribution)** | **1000** |

Tailwind v3/v4 の標準 `z-{N}` は最大 `z-50` (=50)。`z-50` でも全部負ける。

## Why
Leaflet は地図内の UI が常に上に来る前提で設計されているため、外側の overlay は明示的に上書きする必要がある。Tailwind 側に「Leaflet 用の高い z-index プリセット」は存在しない。

## How to apply

### 直し方
modal/overlay のルート要素に **`z-[1100]` 以上** (Tailwind arbitrary value) を付ける:

```tsx
<div className="absolute inset-0 z-[1100] flex items-center justify-center bg-black/35">
  {/* modal content */}
</div>
```

### 設計時の予防
- 地図が出る画面の Architect 設計では、modal/overlay の z-index を**常に 1100+** で書くと明記する
- もしくは Tailwind config に `zIndex: { modal: 1100 }` を定義してチーム共通化:
   ```ts
   theme: { extend: { zIndex: { modal: '1100', toast: '1200' } } }
   ```
- 設計の「挙動仕様」に「modal は地図の上に表示」のような UI 重ね順テストを入れて Reviewer が拾えるようにする (jsdom では物理レイアウトされないので Playwright/E2E が必要)

### 観測しやすい症状
- modal を開くと**背景の dim だけは出る**が中身が見えない (実は地図 controls の下にレンダリングされている)
- モバイルで地図に重ねた tooltip/popup が外側 UI を侵食
- z-index の値を 50 → 100 → 500 と上げても効かない。1000 を超えた瞬間直る
