---
title: Riverpod 3 — Provider の Ref から「自分に依存する provider」を invalidate すると debug だけ CircularDependencyError
category: gotcha
tags: [flutter, riverpod, invalidate, debug-only, flutter-test]
created: 2026-10-15
project: bloom
sources: [bloom 0.2.3 C U2b Reviewer (groupMapProvider / groupKeyStateProvider / GroupKeySync)]
---

## Context
`Provider<GroupKeySync>` の中のクラスが、鍵を受け取った時に `ref.invalidate(groupMapProvider(gid))` と `ref.invalidate(groupKeyStateProvider(gid))` を呼ぶ。この 2 つは内部で `groupKeySyncProvider` を read / watch しているので、依存の向きが逆 (GroupKeySync → 地図 provider → GroupKeySync) になる。

## What
`Ref.invalidate` は `if (kDebugMode) _debugAssertCanDependOn(provider)` で、invalidate 対象の**子孫**に自分の origin がいると `CircularDependencyError` を投げる。debug ビルド / `flutter test` では `syncGroup` が鍵を `put` した直後に例外で止まり (invalidate 以降の状態更新が走らない)、release / profile では何も起きない (assert が無効)。しかも**対象 provider が生きている (購読されている) ときだけ**起きる — 未初期化の provider には子孫が無いので素通りし、単体テストが緑のまま残る。

## Why
Riverpod は「invalidate で依存元を再構築させる」ことを循環とみなす。release で動くのは検査が無いだけで、依存の向き自体は逆転している。

## How to apply
- 通知される側 (地図 / 状態) が `ref.listen(groupKeysChangedProvider, …)` か、鍵の世代を表す provider を `watch` して自分で作り直す向きに揃える。呼ぶ側から invalidate しない。どうしても呼ぶなら `ref.container.invalidate(...)` を使う (検査を通らない) が、依存逆転は残る。
- テスト: 「対象 provider を `container.listen` で生かしたまま、invalidate を起こす操作を呼ぶ」1 本を必ず置く。`flutter test --dart-define=dart.vm.product=true` で kDebugMode を false にでき、debug 限定の assertion を除いた「release 相当」の挙動を同じテストで確かめられる (assert 起因の失敗か本物の不具合かの切り分けに使う)。
- 冗長な invalidate (状態 provider の invalidate が地図 provider を再構築するので地図の invalidate は不要、のような) は、片方だけ外す負のコントロールが生き残る。両方外して初めて赤になる。
