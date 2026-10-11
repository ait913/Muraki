---
title: Flutter の全画面ビューアを「下スワイプで縮んで閉じる」(Instagram ストーリー風) にする骨格
category: pattern
tags: [flutter, viewer, gesture, route, drag-dismiss, ios]
created: 2026-10-10
project: global
sources:
  - Muraki/projects/bloom/.designs/20261010-post-photo-video-quality-viewer-highlight.md §3-5
---

## Context
bloom の投稿ビューア (PageView 横送り + 全画面動画) に「指に追従して縮小・背景フェード、閾値で閉じ、未満で戻る」を足す設計で決めた骨格。

## What
- **route は `opaque: false` + `barrierColor: null`**。黒背景はビューア自身の最背面 `ColoredBox` で描き、静止時は不透明 (見た目は opaque route と同じ)。opaque route だと背面の画面が描かれず、ドラッグ中に「透けて見える」ものが無い
- 変形するのは前景 (PageView + 戻るボタン) だけを包んだ 1 つの `Transform` + `ClipRRect`。背景の `ColoredBox` は変形せず alpha だけ変える
- 見た目は純関数 1 本で決める: `t = clamp(max(dy,0)/H, 0, 1)` → `scale = max(0.6, 1 − 0.4t)`、`backdrop = 1 − clamp(t/0.5)`、`radius = 24·clamp(t/0.1)`、`offset = (dx, max(dy,0))`。閉じる判定も純関数 (`dy ≥ 0.18H` または 下向き速度 ≥ 700 px/s かつ dy > 0)。テストは関数を直接叩ける
- 閉じるときは変形を保ったまま `pop()` し、route の既存フェードで消す (Hero で入口のサムネに戻す案は、入口が複数経路でサムネが無い経路があると破綻する)
- `GestureDetector(onVerticalDrag*)` で包めば `PageView` の横ドラッグとはジェスチャアリーナで軸ごとに分かれる。テキスト入力中はハンドラを null にして無効化
- 時間で進む要素 (写真の自動送りタイマー等) はドラッグ中・シート表示中・入力中に止め、値を保持して再開する

## Why
opaque の切替を後から OverlayEntry に手を入れてやるのは脆い。最初から非 opaque にして背景を自前で持てば、静止時の見た目を変えずに「背面が透ける」効果を得られる。

## How to apply
- テストで速度判定を避けたいときは `tester.timedDrag(..., Duration(seconds: 1))` を使う (`tester.drag` は瞬間移動で速度が大きく出て、閾値未満のドラッグでも閉じてしまう)
- 非 opaque にすると背面の画面が描画され続けるので、背面に重いアニメ (常時 ping 等) があるなら負荷を実機で見る
