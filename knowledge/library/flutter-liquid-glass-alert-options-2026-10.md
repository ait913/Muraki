---
title: Flutter 3.47 の CupertinoAlertDialog は iOS 26 Liquid Glass にならない — 選択肢の現存確認 (2026-10)
category: library
project: global
tags: [flutter, cupertino, liquid-glass, ios26, alert, uialertcontroller, pub]
created: 2026-10-15
sources:
  - https://github.com/flutter/flutter/issues/170310
  - https://developer.apple.com/tutorials/data/documentation/technologyoverviews/adopting-liquid-glass.json
  - https://github.com/berkaycatak/adaptive_platform_ui
  - https://github.com/zonble/flutter_platform_alert
  - https://pub.dev/api/packages/adaptive_dialog
---

## Context
bloom で「はい/いいえ系モーダルを iOS 26 の見た目に」という要望の前調査。bloom は Flutter 3.47.0 / Xcode 26.6 / CupertinoAlertDialog 共通ヘルパー経由。

## What
- flutter/flutter#170310 (Cupertino の Liquid Glass 対応) は 2026-10-10 時点で OPEN、P3 / team-design。Cupertino は cupertino_ui パッケージに分離済みだが glass は入っていない。**Flutter 本体のダイアログは Flutter 自身が描くので、Xcode 26 SDK で再ビルドしても見た目は変わらない**
- Apple: 「システムフレームワークの標準コンポーネント (bars, sheets, popovers, controls) は自動で Liquid Glass を採用」「sheets / action sheets は Liquid Glass」(Adopting Liquid Glass)。UIAlertController を名指しした記述は取得できず、実機/シミュレータでの確認は未実施
- pub (2026-10-15 実測): adaptive_dialog 2.8.3 (Flutter 描画の Cupertino を使うだけ = glass にならない) / flutter_platform_alert 0.9.1 (MIT、iOS は UIAlertController、ボタン数やテキスト入力は限定的) / adaptive_platform_ui 1.0.2 (MIT、2026-10-08、`AdaptiveAlertDialog.show` / `inputShow` が iOS 26+ で native の UIAlertController 派生を出し、入力欄・destructive 対応。ただし toolbar/tab bar 等を含む大型パッケージ) / cupertino_native_better 1.6.0 (platform view 系、アラートは無い) / liquid_glass_renderer 0.2.0-dev.4 (2025-11 から停滞) / native_dialog 最終 2021 (死)
- iOS の HIG: alert は iOS でテキスト入力欄を持てる。sheet の detent は large と medium (約半分) + custom

## Why
Flutter は UI を自前描画するので OS の再スタイリングを受けない。native 部品を使う以外に glass を得る道はない。

## How to apply
- glass 付きアラートが欲しいなら MethodChannel + UIAlertController(.alert) の自前 (Swift 60〜100 行 + Dart ラッパ) か adaptive_platform_ui のアラート部分の写経。iOS 26 未満・テスト用に CupertinoAlertDialog へのフォールバックは残す
- 既存テストが `find.byType(CupertinoAlertDialog)` に依存している PJ は、native 化でウィジェットテストから見えなくなる点を設計に織り込む
