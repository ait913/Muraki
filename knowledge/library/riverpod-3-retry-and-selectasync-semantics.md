---
title: Riverpod 3.4 の自動 retry は Error 派生を再試行しない (record .wait の ParallelWaitError / selectAsync の ProviderException) と selectAsync の「同値なら再 emit しない」
category: library
tags: [riverpod, flutter, retry, ParallelWaitError, selectAsync, FutureProvider]
created: 2026-10-29
project: bloom
sources:
  - "~/.pub-cache/hosted/pub.dev/riverpod-3.4.2/lib/src/core/provider_container.dart:982-996 (defaultRetry)"
  - "~/.pub-cache/hosted/pub.dev/riverpod-3.4.2/lib/src/core/modifiers/select_async.dart"
  - "bloom 実測 2026-10-29 (使い捨て flutter test、bloomRetry を container に渡して /map を 500 → 200 に回復)"
---

## Context

bloom の `groupMapProvider` が「初回は塗りが出ず、開き直すと出る」症状の調査で、Provider が一過性エラーで AsyncError になったあと自動で復帰するかを実測した。

## What

1. `ProviderContainer.defaultRetry` は `error is ProviderException || error is Error` なら **即 null (再試行しない)**。`bloomRetry` のような自前 retry も最後に `defaultRetry` へ委譲すれば同じ。
2. Dart のレコード `(a(), b()).wait` は片方が失敗すると **`ParallelWaitError` (extends Error)** を投げる。元の `ApiException` は `.errors` に入り、`bloomRetry` の「ApiException の 4xx/429 判定」には**到達しない** (= 5xx も 429 も一律「再試行なし」)。実測: `/map` が 500 → 回復後 4 秒待っても `mapCalls=1` のまま AsyncError (`ParallelWaitError<(ApiGroupMap?, DecryptedGroupFootprints?), (AsyncError?, AsyncError?)>`)。
3. `ref.watch(p.selectAsync(...))` が失敗を受けると `ProviderException` になる → 同様に再試行されない。ただし元の provider が後で成功して選択値が変われば再 emit され、依存側は作り直される。
4. `selectAsync` は選択値が前回と **同値なら emit しない** (select_async.dart の `newSelectedValue != lastSelectedValue`)。元 provider の invalidate / 再取得は、選択値が変わらない限り依存側を作り直さない。`await ref.watch(p.future)` から `selectAsync` に替えると「元 provider の再取得に引きずられた偶発的な再計算 (= 偶発的な自己修復)」が消える。
5. **再試行回数 (`_retryCount`) は「依存の変化」か `invalidate(p, asReload: true)` でしか 0 に戻らない** (`core/element.dart:735` の `if (_didChangeDependency) _retryCount = 0;`、`_didChangeDependency` を立てるのは `invalidateSelf(asReload: true)` と watch 先の変化だけ)。成功しても戻らず、`asReload: false` (既定) の invalidate でも戻らない。autoDispose でない provider は、プロセスの生存中に累計 `maxRetries` (10) 回失敗するとそれ以降は自動再試行されない。`asReload: true` の遷移は「`AsyncLoading` + 前回値」で、`.value` は前回値のまま (Architect 2026-10-29、bloom 20261029 doc §5-3)。

## Why

Riverpod 3 は FutureProvider の失敗を既定で指数バックオフ再試行するが、Error 派生は「プログラミングエラー」扱いで除外される。Dart 標準のレコード `.wait` が Error を投げる仕様と組み合わさって、ネットワーク失敗が再試行対象から外れる。

## How to apply

- 非同期 provider で複数 Future を並行取得するときは `(a, b).wait` を使わず、`Future.wait` + 個別 catch、または `try { ... } on ParallelWaitError catch (e) { throw e.errors の最初の非 null }` で元の例外に戻して投げる。
- `selectAsync` 化・select 化のリファクタでは「いつ再取得されるか」の導線 (明示 invalidate / 画面入場) を先に棚卸しする。自己修復が偶発的に効いていた箇所は、リファクタ後に失敗が居座る。
- 失敗からの復帰の契機 (画面入場・[再試行]・再接続) で invalidate するときは `asReload: true` にして再試行回数も戻す。回数を数えるテストは `(n, e) => bloomRetry(n, e) == null ? null : 5ms` のように分類と上限を保ったまま待ちだけ縮める。
- 実測は `ProviderContainer(retry: <本番の retry>)` で行う (テスト harness の `retry: (_, _) => null` では再現しない / 逆に誤って「復帰する」と言えない)。
