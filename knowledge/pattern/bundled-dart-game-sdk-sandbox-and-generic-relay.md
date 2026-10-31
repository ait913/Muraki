---
title: 外部ゲームを Dart ビルド時同梱で受ける SDK — import 許可リストは widgets.dart と基底クラスのフィールドで破れる (型解決が要る) / サーバーは汎用プリミティブだけ持つ (外部開放時の設計。wacha では保留)
category: pattern
tags: [flutter, dart, sdk, sandbox, static-analysis, analyzer, websocket, multiplayer, turn-based, external-developer, on-hold]
status: 外部開放時の設計 (wacha では 2026-10-31 Touri 裁定で保留。platform-core R2 で仕組みごと外した)
created: 2026-10-31
project: wacha
sources:
  - Muraki/projects/wacha/.designs/20261031-platform-core.md §4, §7
  - Muraki/projects/wacha/.knowledge/research-20261031-sdk-platform-architecture.md
  - Flutter 3.47 packages/flutter/lib/src/painting/basic_types.dart (dart:ui の再 export 範囲)
  - flame-1.38.2 lib/src/game/game.dart:28,33 / lib/src/cache/assets_cache.dart (Codex 第 2 意見で発覚、pub-cache で確認)
---

## Context

> **外部開放時の設計 (wacha では保留)**: 2026-10-31 Touri 裁定「SDK 化はまだいい、俺が自由にゲーム追加できる構造だけ」で、wacha の platform-core R2 はチェッカ・提出フロー・境界・「サーバーにゲームコードを置かない」制約を外し、判定が要るゲームはサーバー側ゲームモジュール (Go) に置く形に変えた。本ファイルは**第三者のコードを同梱で受ける時**に再利用するため残す (wacha で再開するならサーバーモジュールが外部コードの実行面になる点が追加の論点)。

wacha で「外部デベロッパーのゲームを Dart パッケージとして受け取り、静的チェック + 人のレビューで次リリースに同梱する」(Apple 2.5.2 / 4.7 の対象外になる方式) を設計した。ゲームの外部通信・保存は SDK 経由に限定し、2 人対戦の realtime サーバーにはゲーム固有コードを置かない、が条件。

## What

1. **import の許可リストだけでは閉じない。** `package:flutter/widgets.dart` を許可した時点で、`services.dart` を import しなくても
   - `WidgetsBinding.instance.defaultBinaryMessenger.send(...)` (= MethodChannel 相当)
   - `View.of(context).platformDispatcher` / `WidgetsBinding.instance.platformDispatcher` (生のプラットフォームメッセージ)
   - `Image.network` / `NetworkImage` (外部 HTTP)
   - `EditableText` (自由入力)
   が型名を import せずに呼べる (Dart は推論された型のメンバーを import なしで呼べる)。**識別子トークンの禁止リスト** (`as dynamic` 経由でも名前は残る) で多くは塞げるが、**名前判定だけでは閉じない**: 許可した `package:flame/game.dart` の `Game` は `Images images = Flame.images;` / `AssetsCache assets = Flame.assets;` をフィールドに持ち、`FlameGame` のサブクラスは `images.load(name, package: '<他パッケージ>')` を禁止名ゼロで呼べる (`images` は一般語で禁止できない)。`Sprite.load` 等は引数 `images` を省くと global cache に落ちる。→ `getResolvedUnit` の型解決層を足し、(a) 静的型が禁止型 (`AssetBundle` / `Images` / `AssetsCache` / `BinaryMessenger` / `PlatformDispatcher`) になる式、(b) 禁止型の引数を宣言に持つ関数への参照 (呼び出し・tear-off、引数を渡していなくても)、(c) dynamic 呼び出し (`avoid_dynamic_calls` 相当) を禁止する。文字列リテラル内は対象外にしてよい。
2. `dart:ui` を禁止しても、`package:flutter/painting.dart` が Canvas / Paint / Color / Offset / Rect 等を再 export するので描画は書ける。`ui.Image` は再 export されないので SDK 側で `typedef GameImage = ui.Image;` を渡す。
3. import 検査は `export` / `part` と条件付き import の `if (dart.library.x) '...'` の URI も全部見る。pubspec は `dependencies` を完全一致の許可表にし、`hook/` (依存側でも build hook が走る) と `dependency_overrides` を名指しで禁止する。import_lint は `dart:` を禁止できない (研究で実測) ので `package:analyzer` の `parseFile` で自前に書く。
4. サーバー (中継) にゲームコードを置かずに 3 種の同期が成り立つ汎用プリミティブ: **手番 (end_turn、手番者だけ受理、期待 turn_no 付き、snapshot 印)・同時公開 (round ごとの commit を両者揃うまで伏せる)・封印 (seal を持ち主にだけ見せ、reveal は両者の票が揃ったときだけ公開。最初の票で手番を凍結)**、+ 結果は**両者の報告が一致したときだけ** finished (不一致・未報告は無効試合。片方の報告で採用すると「戻らなければ勝敗をつけない」原則に反する — R0 で 15 秒採用を書いて Codex に HIGH で指摘された)。開始時に秘密を入れる型は `requiredSeals` で「両者の seal 前は手番を進めない・seal していない側を待ち扱い」にする。「サーバーが秘密を持って判定」型 (ヒット&ブロー) は、預かり + 持ち主端末が判定 + 終局で相手端末が検算、で置き換えられる。「両者に隠す値」(ふうせんパンクの閾値) はこれでは無理で、別プリミティブ (サーバー乱数 + compare) が要る。
5. 2 端末で同じ乱数列が要るなら Dart の `Random(seed)` でなく SDK 内に固定アルゴリズム (mulberry32 等) を持つ — 2 人のアプリの版が違うと Dart SDK も違い得る。

## Why

同梱方式の安全性は「静的チェック + 人のレビュー」でしか担保できず、静的チェックの穴は Flutter の便利 API 側にある。サーバー側をゲーム非依存にしておくと、外部ゲームの審査範囲がクライアントの 1 パッケージに閉じる。

## How to apply

- 同種の「プラグイン / 外部コードを同梱」設計では、許可した上位ライブラリから**型名を import せずに届くメンバー**を列挙し (binding・view・image provider・テキスト入力・platform view)、識別子禁止で塞ぐ。さらに**許可したクラスを継承したときに付いてくるフィールド・getter** (`FlameGame.images` 等) と、**省略可能な引数が global に落ちる関数**を pub-cache で grep し、型解決層で塞ぐ。fixture に「`as dynamic` 経由」「継承フィールド経由 (禁止名なし)」「文字列リテラルだけ (違反なし)」を入れて負のコントロールにする。
- 境界の目的に「同梱アセットを他ゲームから読めない」を置かない — IPA を展開すれば誰でも読める。止めるのは global 状態 (`Flame.bundle` は代入できる static) の書き換えと、他パッケージへの暗黙の依存。
- 復元 (replay) でゲームのコールバックを再実行するなら、復元中は送信を禁止し、復元完了の通知 (`onReady`) で「まだ送っていない行動」だけを送らせる。SDK の last_seq は base_seq − 1 に初期化する (snapshot から再生すると欠番検知と衝突する)。
- 中継サーバーの検証規則と、ゲーム開発者向けのテスト用フェイク (`FakeMatch`) を同じ挙動仕様の ID で両方検査する (二重実装の乖離を表で止める)。
