---
title: Flutter テストで AppLifecycleListener 起点の非同期 I/O は runAsync の中から送らないと偽 RED になる
category: gotcha
tags: [flutter, flutter-test, AppLifecycleListener, runAsync, drift, riverpod]
created: 2026-11-04
project: bloom
sources: [bloom/app/test/reviewer_offline/lifecycle_test.dart]
---

## Context

bloom オフライン投稿 (2026-11-04)。`hidden` に入る瞬間に outbox runner を 1 回 pump する配線 (`AppLifecycleListener.onStateChange`) をブラックボックスで検証した。

## What

- `tester.binding.handleAppLifecycleStateChanged(hidden)` を **testWidgets の fake zone で直接呼ぶ**と、listener 内の `run(runner.resume(...))` が drift の実 I/O を待つため pump されず、行が 1 ミリも動かない (偽 RED「配線が無い」)。`tester.runAsync(() async { binding.handle…; await Future.delayed(500ms); })` の中から送る。
- `resumed → hidden` を 1 回で送ると binding が inactive を合成して同期的に 2 回通知し、**flush が起きない**。OS 実機と同じ「`inactive` と `hidden` を別メッセージで」送る (間に 500ms)。
- 観測は runner 内部ではなく `beginBackgroundWork` の回数 (fake inbox) と行の状態遷移で取る。provider の runner は `dbProvider` / `outboxSupportRootProvider` / `postMediaProcessorProvider` / `backgroundUploaderProvider` / `uploadResultInboxProvider` を override すれば本物のまま立つ。runner の時計は実 `DateTime.now()` なので、`nextAttemptAt` の seed は `DateTime.now()` 基準 (テスト Env の `e.now` 基準にすると過去 = 迂回なしで due になり、迂回の検証にならない)。

## Why

Riverpod provider が起こす drift の `await` は実 I/O で、fake async zone では進まない。AppLifecycleListener の通知は同期的に fan-out するので、zone を間違えると「通知は届いたが後続が走らない」状態になる。

## How to apply

lifecycle・WS・timer 起点の「黒箱の副作用」テストは、(1) 送信を `runAsync` の中に置く、(2) OS が送る順序そのまま 1 状態ずつ送る、(3) 副作用は fake の呼び出し回数で数える。「配線が無い」と書く前に、同じ送信を `runAsync` 内でやり直す probe を 1 本回す。
