---
title: Flutter アプリのストア用実画面は「偽サーバー内蔵の撮影エントリポイント」で撮る (タップ不要・本番を汚さない)
category: pattern
tags: [app-store, screenshots, flutter, simulator, simctl, riverpod, multiplayer]
created: 2026-11-06
project: global
sources:
  - projects/wacha/.designs/20261106-testflight-feedback-1.md §6-3
---

## Context
wacha (2 人対戦の Flutter アプリ) のストア画像の設計で、Leader の前提は「シミュレータ 2 台で本番かローカルに繋いで撮る」だった。Mac に UI 操作の道具 (idb / maestro / cliclick) が無く (`which` で確認)、AI のロールはタップできない。本番に繋ぐとテストユーザーと試合が残り、ローカルサーバーは未整備だった。

## What
- 外部依存 (HTTP・WS・Keychain・ハプティクス等) が Riverpod の provider で差し替えられるアプリなら、`app/tool/shots/main_shots.dart` という**別エントリポイント**で provider を override し、HTTP は `package:http/testing.dart` の `MockClient`、WS は台本を流す偽ソケットにすると、相手の操作も含めて決まった画面状態に自動で到達する。1 台・タップなし・サーバーなし
- 試合の途中の状態は「復元 (replay)」の経路で 1 イベント渡すのが一番安い: サーバー判定のゲームは最後の状態 (view) 1 つ、手番側確定のゲームは snapshot 付きの手番 1 つ。物理の座標は手で書かず、ホストの `flutter test` で物理を回して静止した値を書き出す
- どの画面を撮るかは**アプリのコンテナにファイルで渡す**: 撮影スクリプトが `xcrun simctl get_app_container <udid> <bundle> data` の `Library/Caches/<name>` に id を書き、撮影用 `main` がそれを読む。`SIMCTL_CHILD_<NAME>=<id> xcrun simctl launch …` の環境変数は **iOS の Flutter 3.47 では Dart の `Platform.environment` が空で届かない** (wacha 2026-11-06 実測。キー一覧を例外で出して確認)。ビルドは `flutter build ios --simulator --debug -t tool/shots/main_shots.dart` の 1 回だけ (`--dart-define` だと撮影ごとに再ビルド)
- 一時的な演出 (受信スタンプ 1.8 秒等) は、尺を provider (`StampTiming`) にしておき撮影エントリだけ保持を延ばす。本番コードに撮影フラグを入れない
- 撮影専用のシミュレータを `xcrun simctl create` で作って最後に消す (他 PJ の端末を触らない)。`simctl status_bar override` と `simctl ui appearance dark|light` で時刻と外観を揃える
- 台本の腐りは、同じ override で `WachaApp` を `flutter test` に pump して着地画面の Key を確かめるテストで止める

## Why
人の手作業 (2 台を交互にタップ) は撮り直しのたびに同じ手間で、AI だけでは回らない。本番接続は後始末が要り、ローカルサーバーは準備が重い。provider の差し替え口はテストのために既にあるので、追加は台本と小さな偽ソケットだけで済む。

## How to apply
ストア画像・LP 素材の撮影を設計するとき、まず「UI 操作の道具があるか」「外部依存を差し替える口があるか」を確かめる。口があれば撮影エントリポイント + 台本 + `simctl` で、合成は `pattern/store-screenshot-html-port-between-apps.md` の HTML パイプラインに渡す。`lib/main.dart` から `tool/shots/` を import しないこと (本番ビルドに入れない) をテストで固定する。
