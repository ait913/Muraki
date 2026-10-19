---
title: Riverpod 3 — live の provider を demo / 他の変化から切り、再取得中は前回値を出し続ける
category: pattern
tags: [flutter, riverpod, select, selectAsync, invalidate, reload, AsyncValue, performance]
created: 2026-10-19
project: bloom
sources: [bloom 0.2.4 パッチ設計 (.designs/20261019-patch-0.2.4-group-perf-head-track-crash.md), riverpod-3.4.2/lib/src/core/element.dart:51,67 / async_value.dart:85-96,243-260]
---

## Context
bloom 0.2.3 で S1⇄S2 の行き来が重くなった。1 ユーザーが 1 分に `GET /v1/groups/{gid}` を 119 回。原因は (1) live でも `DemoState` を毎回新しいオブジェクトに置換する `markRead`、(2) `DemoState` を `select` なしで watch する REST provider、(3) 取得中に地図 widget が unmount される `AsyncValue.when(loading:)`。

## What
- **`ref.watch(p).field` は select ではない。** `p` 全体を watch してから `.field` を読むだけで、`p` が変わるたびに再構築される。`ref.watch(p.select((s) => s.field))` と書く。
- **`==` を持たない state を `state = state.copyWith(...)` で置換すると、中身が同じでも全 watcher が再構築される。** 値が変わらない更新は `if (変化なし) return;` で state を置換しない。
- **live の provider が demo の中身まで追う必要は無い。** 「seeded の間だけ全体を watch し、そうでなければ seeded だけ」のヘルパ: `T? watchIfActive(Ref ref) { final on = ref.watch(p.select((s) => s.on)); return on ? ref.watch(p) : null; }`。provider 内の動的な watch は許される。
- **`ref.invalidate` / `ref.refresh` は refresh、`ref.watch` した依存の変化は reload。** riverpod 3.4.2 は `seamless = !ref.isReload` で、refresh の `AsyncLoading` は前回値を持ち `when` が既定 (`skipLoadingOnRefresh: true`) で `loading:` を呼ばない。**reload は既定 (`skipLoadingOnReload: false`) で `loading:` を呼ぶ**ので、依存 (`await ref.watch(other.future)`) が再計算されるたびに子の画面が skeleton / 空に戻り、その下の platform view (地図) が unmount される。
- **対策は 2 段**: (a) 子 provider は親の「必要な部分」だけに依存する (`ref.watch(parent.selectAsync(toInputs))`。`toInputs` は `==` を持つ値型を返す)。(b) 画面側は `when(loading:)` でなく `final data = async.value;` で前回値を持ち続ける (`data == null` のときだけ空・skeleton)。または `when(skipLoadingOnReload: true)`。
- 重い純計算は `Isolate.run`。クロージャは**トップレベル関数の中で作る** (呼び手の中で作ると Ref / this を含む文脈ごと送ろうとして ArgumentError)。入力が同一オブジェクト (`identical`) なら前回の結果を再利用する memo を併用する。テストでは runner を差し替え可能にし、`flutter_test_config.dart` で同期実行に固定する。

## Why
Riverpod の再構築は「値が `!=` か」で決まり、`when` の分岐は「refresh か reload か」で決まる。両方とも見た目には出ず、実害 (REST の連打・地図の作り直し) として初めて現れる。ブリーフの「N 箇所が全部 rebuild」は、箇所ごとに「select にできるか / seeded の間だけ全体か / 変えないか」を仕分けて初めて直せる。

## How to apply
- 横断的に watch されている state に変更を入れる前に `grep -rn "ref.watch(<p>)" lib` を全数表にし、各行に処置 (select / ヘルパ / 変更なし) と理由を割り当てる。`.field` 付きの行を select 済みと数えない。
- 「前回値を出し続ける」仕様は、`async.value == null` のときだけ空にする、と挙動仕様に書き、reload 中の Element 同一性 (`tester.element(find.byType(X))` が前後で `identical`) をテストにする。
- 子 provider の再構築を減らすなら、親の変化のうち子が使う部分を値型にして `selectAsync` に渡し、「ビーコンだけ変わった親」では子が作り直されない、を負のコントロールにする。
- 関連: [[riverpod-invalidate-dependent-provider-from-provider-ref-debug-circular]]
