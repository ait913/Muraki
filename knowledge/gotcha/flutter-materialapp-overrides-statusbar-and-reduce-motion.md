---
title: Flutter の既定値が黙って効く 3 点 (ステータスバーの文字色 / 視差の軽減で尺が 5% / Positioned.fromRect の押し込みで切れる)
category: gotcha
project: wacha
tags: [flutter, dark-mode, status-bar, SystemUiOverlayStyle, reduce-motion, AnimationBehavior, Positioned, clip]
created: 2026-11-06
sources:
  - Flutter 3.47.0 packages/flutter/lib/src/material/app.dart:1011-1013
  - wacha TestFlight build 10002 フィードバック修正 (sessions/2026-10-31-76c68c35 #115〜#118)
  - projects/wacha/.knowledge/research-20261106-testflight-feedback-1.md
---

## Context

wacha は色を自前 token + `MediaQuery.platformBrightnessOf` で切り替え、`MaterialApp` には theme を渡していなかった。実機のダークモードでステータスバーの時刻が黒のまま、という指摘から 3 つの「既定値の罠」が出た。どれもテストは緑のまま実機でだけ見える。

## What

1. **ステータスバーの文字色は `MaterialApp` の theme が毎 build 上書きする。** `MaterialApp` は build のたびに `SystemChrome.setSystemUIOverlayStyle(theme.brightness == dark ? light : dark)` を呼ぶ。theme を渡さないと既定 `ThemeData()` (ライト) なので、端末がダークでも黒文字になる。画面側で `SystemChrome` / `AnnotatedRegion` を 1 回呼んでも次の build で戻される。
2. **`MediaQuery.disableAnimations` (iOS「視差効果を減らす」) が true だと `AnimationController` は duration を約 5% に縮める** (既定 `AnimationBehavior.normal`)。「軽減時は動かさず同じ尺だけ表示する」仕様のものは、純関数が正しくても約 90ms で消える。
3. **`Positioned.fromRect(rect: 小さい枠, child: 自然寸法が大きい部品)` は子を枠の寸法に強制する。** 内側が `Stack` (既定 `Clip.hardEdge`) だと、はみ出した輪郭・厚みが切れる。wacha は 56×56 の基準枠に 64×68 の丸ボタンを入れ、下端が切れたまま 3 ビルド出ていた。

## Why

- 1 は色を自前で持つアプリほど踏む (Theme を使わないので渡し忘れる)。
- 2 はウィジェットテストで `disableAnimations: true` を与えて時間を進めないと出ない。
- 3 は論理矩形 (`getRect`) を検査するテストでは緑になる。描画がはみ出して切れることは実描画でしか見えない。ストア画像用に実画面を撮って初めて気づいた。

## How to apply

- ダークモード対応は `MaterialApp(theme:, darkTheme:, themeMode: ThemeMode.system)` を必ず渡す。検査は `tester.platformDispatcher.platformBrightnessTestValue` を変えて `SystemChrome.latestStyle` を見る。
- 「視差の軽減でも尺を保つ」演出の controller は `animationBehavior: AnimationBehavior.preserve`。設計 doc に軽減時の挙動を書くとき、尺を保つのか 0ms にするのかを部品ごとに明記する。
- 基準枠と部品の実寸 (厚み込み) が違うときは、中心を合わせて実寸の矩形で置く。新しい画面は 1 回は実描画 (シミュレータの素材) を端から端まで目視する。
