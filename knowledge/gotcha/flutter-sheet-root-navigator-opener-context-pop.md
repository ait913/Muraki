---
title: Flutter のシートを root Navigator に移すと「開いた側の context で pop」が別の route を閉じる
category: gotcha
tags: [flutter, go_router, StatefulShellRoute, showModalBottomSheet, CupertinoSheetRoute, navigator]
created: 2026-10-06
project: bloom
sources:
  - projects/bloom/.designs/20261006-ui-fixes-batch-2.md §3-4
  - app/lib/ui/s3_map.dart (_onCandidateTap, version/0.2.0 4606abb)
---

## Context
bloom の UI 修正第 2 バッチの設計。共通の `showBloomSheet` (showModalBottomSheet) に `useRootNavigator: true` が無く、タブ内の画面 (StatefulShellRoute の branch の入れ子 Navigator) から開くとシートがタブバーの手前で止まっていた。1 行足せば直る修正に見えた。

## What
シートの中身のボタンが、シート自身の context ではなく**シートを開いた画面の context** (クロージャで捕まえた外側の `context`) で `Navigator.of(context).pop()` していた箇所があった (S3 の候補セルシート)。
- 修正前: シートも入れ子 Navigator に積まれていたので、外側の context の Navigator = シートの Navigator で、たまたまシートが閉じていた
- 修正後: シートは root に移るが、外側の context の Navigator は入れ子のまま → **シートは開いたまま、地図タブの route を pop しようとする**

`showCupertinoSheet` / `CupertinoSheetRoute` は常に root に push するので、同じ問題がシートの Cupertino 化でも起きる。

## Why
`Navigator.of(context)` は context の祖先で最も近い Navigator を返す。シートの push 先を変えても、呼び出し元の画面の祖先 Navigator は変わらない。入れ子 Navigator 時代は「どちらの context でも同じ Navigator」だったので、誤った context を使っていても動いていた (潜在バグ)。

## How to apply
- シートの push 先 (`useRootNavigator`、Cupertino シート化) を変える設計では、全呼び出し元について「シートの中で pop / push に使っている context はシート自身のものか」を grep で確かめる。外側の context を捕まえているもの (`showX(context, Widget(onTap: () => Navigator.of(context).pop()))` の形) は、シート本文を `Builder(builder: (sheetContext) => …)` で包んで `Navigator.of(sheetContext).pop()` にする
- シートを閉じてから次の画面・シートを開く処理は、pop の**前に** `GoRouter.of(context)` / `Navigator.of(context, rootNavigator: true).context` を握る (pop 後の context に依存しない)
- 中で `rootNavigator: true` を既に使っている push (全画面の route) は着地先が変わらないので対象外
