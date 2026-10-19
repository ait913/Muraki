---
title: Flutter の Navigator.push は操作中のポインタを cancel する (長押し→route を開く→そのまま滑らせる、は成立しない)
category: gotcha
tags: [flutter, navigator, gesture, long-press, design-review]
created: 2026-10-11
project: global
sources: [projects/bloom/.designs/20261011-sticker-poke.md §4-3 §4-4 K-109, sessions/2026-10-11 bloom sticker-poke Reviewer]
---

## Context

bloom 0.2.2 スタンプ攻撃の設計は「アバターを長押し → パレットを root Navigator に push → **指を離さずに** セルへ滑らせて離す = 送信」(Zenly 風)。`GestureDetector(onLongPressStart: push, onLongPressMoveUpdate: hover, onLongPressEnd: release)` で実装され、Reviewer の widget テスト (K-109) だけが落ちた。

## What

`onLongPressStart` の中で `Navigator.push(...)` すると、その指の以降のイベントは **`onLongPressMoveUpdate` / `onLongPressEnd` に来ず、`onLongPressCancel` が 1 回呼ばれて終わる**。素の `GestureDetector` + `PageRouteBuilder(opaque: false)` の最小再現で `(moves, ends, cancels) == (0, 0, 1)`。`GestureDetector` のコールバックを直接呼べばパレット側 (`hover` で拡大・`release` で送信) は正常 = 壊れているのは「route を push する」設計の層。テストの偽 fail ではなくフレームワーク仕様で、実機でも同じ (Navigator が push 時に `_cancelActivePointers` を呼ぶ)。

## Why

Navigator は route 遷移の際に、遷移元の widget が操作中だった全ポインタを cancel して「遷移中に指が前の画面を操作し続ける」事故を防ぐ。長押し中に route を積む設計はこの仕組みと正面衝突する。

## How to apply

- 「長押し → 指を離さず選択」型の UI (コンテキストメニュー風・リアクションピッカー) は **route を push せず `OverlayEntry` (root Overlay) で出す**。同じ最小再現で `Overlay.of(context, rootOverlay: true).insert(OverlayEntry(...))` に替えると `(moves, ends, cancels) == (1, 1, 0)` (Reviewer が確認済み)。ポインタを持つ `GestureDetector` を unmount しない限り move / up はそのまま届く。
- 設計で route を使うなら「長押し → 離す → パレットが出る → 別のタップで選ぶ」の 2 ジェスチャにする。
- Architect: 「指を滑らせて離す」系の仕様を書いたら、K-109 型の「ジェスチャを実際に流して送信される」テストを層の割り当てに入れる。コールバック直呼びのテストだけだと緑になる。
- Reviewer: 症状が「hover / release が効かない」なら、素の `GestureDetector` に同じ操作 (`startGesture` → `pump(600ms)` → `moveTo` → `up`) を流し、`onLongPressStart` で route を push した版との差で切り分ける (`onLongPressCancel` の回数を数える)。
