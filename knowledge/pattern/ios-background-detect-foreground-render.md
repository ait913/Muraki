---
title: iOS で「背景で検知 → 重い描画は前景で」を分ける (背景は Metal 不可、検知の判定者は Swift 1 つ)
category: pattern
tags: [ios, background, metal, gpu, region-monitoring, maplibre, avfoundation, flutter, state-machine]
created: 2026-10-11
project: global
sources:
  - https://developer.apple.com/documentation/metal/preparing-your-metal-app-to-run-in-the-background
  - https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest
  - https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoring(for:)
  - projects/bloom/.designs/20261011-places-trips-vlog.md
---

## Context
bloom 0.2.2 の「旅から帰ったら vlog を自動生成して通知」の設計。要望の文言は「帰宅を検知して『vlog できたよ』と通知」だった。

## What
- iOS は背景のアプリに GPU を使わせない。背景に入った後の Metal command buffer はエラーで実行されない (Apple の Metal 文書)。MapLibre の snapshot (Metal 描画) も、Core Animation を重ねる動画合成も、背景で起こされた数秒 (region / SLC / visit の relaunch) では作れない。
- `BGContinuedProcessingTaskRequest` (iOS 26+) は前景から人の操作で始めた処理だけを背景で続けられる。帰宅の瞬間に自動で始める用途には使えない。
- `CLLocationManager.startMonitoring(for:)` は Apple の文書上 `deprecatedAt: 27.2` (後継は `CLMonitor`、iOS 17+)。iOS 15 配備では今も使える。region は正確な位置 (full accuracy) が無いと使えない。
- Flutter で背景の Dart が DB に触れない構成 (headless engine は空、ネイティブが JSONL に貯める) では、背景で判定して通知するには判定を Swift に置くしかない。Dart にも同じ規則を書くと 2 実装が食い違う。

## Why
Metal の背景制限は前景アプリの描画性能を守るための OS の方針で、タスクの種類で回避できない。

## How to apply
- 「背景で X を検知したら Y を作って知らせる」型の要望は、Y が GPU を使うなら「通知 → 開いたら自動で作る → 画面に進捗」に分け、通知の文言を事実 (まだできていない) に合わせる。要望の文言どおりにできないことは設計 doc の残論点に根拠付きで上げる。
- 検知の判定者は Swift の純粋な状態機械 1 つにし、効果 (JSONL への emit / region / 通知 / 逆ジオ) を戻り値で返す形にすると XCTest で叩ける。Dart は JSONL の drain で写すだけ。
- 判定の入力が背景で途切れても (記録がまばら)、終わりのサンプルで遡って確定できる遷移を入れる (6 時間の滞在の途中に記録が無くても、戻った時点で「最後に外にいた時刻 − 遠くに出た時刻」で判定)。
