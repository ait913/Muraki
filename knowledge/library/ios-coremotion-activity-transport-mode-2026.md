---
title: CMMotionActivityManager で移動手段を判定する時の事実 (電車は専用区分なし / 履歴 7 日 / NSMotionUsageDescription 必須)
category: library
project: global
tags: [ios, coremotion, cmmotionactivity, motion-permission, transport-mode, flutter]
created: 2026-10-11
sources:
  - https://developer.apple.com/documentation/coremotion/cmmotionactivitymanager
  - https://developer.apple.com/documentation/coremotion/cmmotionactivity
  - https://developer.apple.com/documentation/coremotion/cmmotionactivitymanager/queryactivitystarting(from:to:to:withhandler:)
  - https://developer.apple.com/forums/thread/685532
  - https://pub.dev/packages/flutter_activity_recognition
---

## Context
Bloom 0.2.2 の移動手段判定 (徒歩/車/電車) の事前調査 (2026-10-11)。

## What
- `CMMotionActivity` の区分は stationary / walking / running / automotive / cycling / unknown + confidence。**互いに排他でない** (停車中の車は automotive と stationary が同時 true、全 false もあり得る)。**電車・公共交通の区分は無い** (公式 doc に記述なし。電車が automotive に入るか全 false かは Apple 非公表で出典なし → 実機ログで決める)。
- `NSMotionUsageDescription` が Info.plist に無いと API 呼び出しでクラッシュ。初回アクセスで「モーションとフィットネス」許可プロンプト。
- `queryActivityStarting(from:to:)` の履歴は**最大 7 日** (公式 .md に明記)。範囲にサンプルが無いと CMErrorUnknown。
- バックグラウンド: `startActivityUpdates` は変化時のみ配信 (Apple forum 685532)。アプリ非実行中は走らない → 前景復帰で query して後追いが定石。
- Flutter: `flutter_activity_recognition` が iOS で CMMotionActivityManager を使う (要 NSMotionUsageDescription)。permission_handler 経由で要求しない (別 plugin の注意書き)。自前 Swift ブリッジでも数十行。

## Why
Core Motion はモーション coprocessor の分類結果を返すだけで、交通機関の語彙を持たない。

## How to apply
電車判定は CoreMotion 単独で作らず、速度 (CLLocation.speed) + 駅/線路近接 (MKLocalSearch POI 等) との合成で、実機の電車ログを先に取ってから閾値を決める。
