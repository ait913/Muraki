---
title: flutter test で plugin 同梱 ffi は動かない — ホスト dylib を dlopen 注入する
category: gotcha
tags: [flutter, ffi, h3, flutter-test, harness]
created: 2026-08-20
project: bloom
sources: [worktrees/bloom-p2a-location/app/test/reviewer/_h3_host.dart]
---

## Context

bloom P2a のレビューで、集計パイプライン (h3_flutter の `latLngToCell`) を `flutter test` (ホスト VM) で回そうとした。

## What

`h3_flutter`/`h3_ffi` は `H3Factory().load()` が **process 内 symbol (RTLD_DEFAULT)** を lookup する設計で、ホストの `flutter test` では plugin のネイティブ実体がリンクされず `Failed to lookup symbol 'degsToRads'` で全滅する。pub 配布物の `c/h3/` ディレクトリも空 (git submodule が同梱されない) なので自前ビルドの足場もない。

## Why

flutter plugin の C ライブラリは iOS/Android ビルドにしか組み込まれない。ホスト VM テストでは dart:ffi の lookup 先が無い。ただし macOS の dlopen は既定 **RTLD_GLOBAL** なので、テスト側で同名 symbol を持つ dylib を 1 回 open すれば RTLD_DEFAULT lookup が通るようになる。

## How to apply

- `brew install h3` → setUpAll で `DynamicLibrary.open('/opt/homebrew/lib/libh3.dylib')` するだけで h3_ffi がそのまま動く (bloom: `app/test/reviewer/_h3_host.dart`)。
- 同型の plugin ffi (sqlite3 は drift が NativeDatabase でホスト対応済みなので不要) でも「brew 等のホスト版 dylib を process 注入」が最小の回避。
- Architect への含意: 設計 doc の「テスト基盤」にホスト実行の前提 (brew パッケージ) を明記する。判定への含意: この失敗は環境依存に分類し、実装バグに帰属しない。
