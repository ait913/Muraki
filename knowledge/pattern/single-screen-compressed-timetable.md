---
title: 1 画面圧縮タイムライン (時間割 / シフト表 / カレンダー日 view)
category: pattern
tags: [layout, css-grid, percent-positioning, cluster-column-split, mobile-first, atender]
created: 2026-05-27
project: global
sources:
  - https://developers.google.com/calendar (Google Calendar 日 view)
  - https://fullcalendar.io/docs/timegrid-view
  - Atender v6 設計 (Muraki/projects/atender/.designs/20260527-v6-room-calendar-timetable.md)
---

## Context

「複数メンバーの時間割を 1 画面に縦スクロールなしで並べる」「シフト表を viewport 高さに圧縮表示する」「Google Calendar 日 view のように重なるイベントを横並びで表現する」要件を、CSS Grid + パーセント絶対配置 + Cluster column split で実現する pattern。Atender v6 の `RoomTimetable` で確立。

外部ライブラリ (FullCalendar / react-big-calendar) なしで、Tailwind + 素の CSS だけで完結する。

## What

### 構成

1. **viewport - chrome の縦領域確保**
   - `height: calc(100dvh - var(--chrome-top) - var(--chrome-bottom) - env(safe-area-inset-bottom, 0px))`
   - `min-height: 320px` で潰れ防止
   - `chrome-top` / `chrome-bottom` は CSS variable で集約 (TopBar / BottomTab / tab / header の合計)

2. **min/max minute → viewRange (30 分スナップ)**
   ```ts
   function computeViewRange(events): { minMinute, maxMinute } {
     if (events.length === 0) return { 9*60, 18*60 };
     const min = Math.floor(Math.min(...starts) / 30) * 30;
     const max = Math.ceil(Math.max(...ends) / 30) * 30;
     return { minMinute: min, maxMinute: max };
   }
   ```

3. **イベントを percent 配置**
   ```ts
   top = ((event.startMinute - range.minMinute) / (range.maxMinute - range.minMinute)) * 100;
   height = ((event.endMinute - event.startMinute) / (range.maxMinute - range.minMinute)) * 100;
   ```
   `top` / `height` は親のパーセント (= viewRange を 100% とする)。これで viewport がどんな高さでも比率は保たれる。

4. **Cluster column split (Google Cal 風)**
   - 同じ列 (= 同曜日) の中で時刻が重なる event を Cluster 化
   - Cluster 内で greedy lane 割当 (最も早く空く lane に各 event を入れる、なければ新 lane)
   - 各 event の left = `(lane / laneCount) * 100%`、width = `(100 / laneCount)%`

5. **横軸の動的列数**
   - 月-金のみなら 5 列、土日にイベントがあれば 7 列
   - `gridTemplateColumns: 40px repeat(${days.length}, minmax(0, 1fr))`

### 擬似コード (Cluster split)

```
sort events by (startMinute asc, endMinute asc)
cluster = []; clusterEnd = -Inf
for e in sorted:
  if e.startMinute >= clusterEnd:
    flush cluster; cluster = [e]
  else: cluster.push(e); clusterEnd = max(clusterEnd, e.endMinute)
flush cluster

for cluster in clusters:
  lanes = []  // lanes[i] = last assigned event's endMinute on lane i
  for e in cluster:
    placed = -1
    for i in 0..lanes.length-1:
      if lanes[i] <= e.startMinute: placed = i; break
    if placed == -1: placed = lanes.length; lanes.push(e.endMinute)
    else: lanes[placed] = e.endMinute
    e.lane = placed
  laneCount = lanes.length
  for e in cluster: e.laneCount = laneCount
```

## Why

- **外部依存なし**: FullCalendar (200KB+) や react-big-calendar (100KB+) を入れずに同等表示
- **viewport 適応**: percent 配置 + `dvh` で iPhone SE (320×568) でも Pixel 9 (412×915) でも 1 画面に収まる
- **column split のシンプルさ**: greedy アルゴリズムは O(N log N + N × laneCount)、N=100 でも数ms。FullCalendar の overlap 計算と同等の見た目を 50 行で実装可
- **メンタル モデルが Google Cal と同じ**: 学生 / 社会人が既に知っている「重なる予定は横並び」の表示を踏襲

## How to apply

新規アプリで「複数ユーザーの時間情報を 1 画面圧縮表示」する場面:

1. データ型を `{ id, dayOfWeek | date, startMinute, endMinute, ...meta }` に正規化
2. `chrome-top` / `chrome-bottom` を CSS variable に集約 (page chrome 変更時の保守を簡単に)
3. `computeViewRange` を 30 分スナップで実装 (= UI に余白が出ない)
4. Cluster 分割 → lane 割当 を pure function 化、test で 5-10 ケース固める
5. 描画は `position: absolute` + `top/height/left/width` パーセントで完結。Grid は曜日列の枠だけに使う
6. min-height (例: 320px) で極小画面の潰れ防止

### やらない

- イベント数が 1 day で 50+ になる用途 (横方向の lane が多すぎて潰れる → 縦スクロール許容に切り替えるべき)
- 分単位の正確な位置決め (CSS 1px = 数分単位の誤差は受容、ピクセル完璧は不要)
- 全曜日固定 7 列 (= 土日空でも 7 列維持) は mobile では各列が狭くなりすぎる、動的縮退推奨

## 反例 / 限界

- 同曜日同時刻に 5+ event が重なると lane が増えすぎて 1 ブロックが 20% 幅以下に潰れる。デザイン妥協が必要 (例: 「+ N 件」集約)
- イベントの開始終了が `00:00` を跨ぐと range 計算が破綻 (negative minute)。日跨ぎ前提なら別アルゴリズム必要
- jsdom テストでは `calc()` / `dvh` が評価されないため、`getComputedStyle` ではなく style 属性の生文字列を assert する
