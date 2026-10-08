---
title: Flutter 3.47 の showCupertinoSheet は showDragHandle を捨て、route の掴み手はダークで見えない
category: gotcha
tags: [flutter, cupertino, sheet, dark-mode, CupertinoDynamicColor]
created: 2026-10-07
project: global
sources:
  - /opt/homebrew/share/flutter/packages/flutter/lib/src/cupertino/sheet.dart (Flutter 3.47.0) :173-251, :692-731, :777-783, :819-824, :887-889
  - /opt/homebrew/share/flutter/packages/flutter/lib/src/cupertino/colors.dart :410-420
  - bloom .designs/20261007-ui-fixes-batch-3.md §9
---

## Context
bloom で S6/S8 を「iOS 純正風の半分シート・背面縮小なし・暗転あり」にする設計中、ブリーフの `showCupertinoSheet(topGap: 0.5, showDragHandle: true)` を SDK で確かめた。

## What
- `showCupertinoSheet` は `showDragHandle` 引数を受け取るが、`CupertinoSheetRoute(...)` を作るときに渡していない (nested / 非 nested の両経路)。指定しても掴み手は出ない
- `CupertinoSheetRoute(showDragHandle: true)` を直接 push すると出るが、色は `CupertinoColors.tertiaryLabel` を **resolve せずに** `ShapeDecoration` に入れている。`CupertinoDynamicColor` は resolve しないと light の値 (`rgba(60,60,67,0.30)`) なので、常時ダークのアプリの面では見えない
- `topGap` を指定すると `delegatedTransition == null` / `canTransitionFrom == false` で背面が縮まない (逆に「縮ませたい」設計では topGap を渡せない)
- `barrierColor` = transparent / `barrierDismissible` = false は getter なので、`CupertinoSheetRoute` を継承して上書きすれば暗転と外タップ閉じを足せる

## Why
便利関数の引数と route の引数が別々に増えた際の渡し漏れ。掴み手の色は dark/light を CupertinoTheme で resolve する前提の書き方になっていない。

## How to apply
- 半分シート + 暗転が欲しいなら `CupertinoSheetRoute` を継承した route を `Navigator.of(context, rootNavigator: true).push` する (`showCupertinoSheet` を使わない)
- 掴み手はアプリ側の自前 (明色) に統一し、`showDragHandle: false`
- SDK の便利関数で「引数が効く」と書く前に、その関数が route / widget に引数を渡しているかを開いて確かめる
