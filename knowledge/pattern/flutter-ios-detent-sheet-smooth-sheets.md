---
title: Flutter で iOS の detent シート (fit / medium / large) — smooth_sheets 1.2.1 + 毎レイアウトで段数を決める SnapGrid
category: pattern
tags: [flutter, ios, bottomsheet, detent, smooth_sheets, cupertino, material_ui]
created: 2026-10-08
project: bloom
sources:
  - bloom .designs/20261008-sheet-detents-native-dialogs.md
  - smooth_sheets 1.2.1 / 1.3.0 の pub.dev tarball (lib/src/{snap_grid,modal,scrollable,viewport,model}.dart)
  - scratchpad の使い捨て Flutter 3.47.0 プロジェクトでの widget test 実走
---

## Context

bloom で「中身が少なければ中身の高さ、多ければ半分 (medium) で開いて上スワイプで全高 (large)、中身のスクロールは large になってから、背面は縮まない、暗転 + 外タップで閉じる」(SwiftUI の `.presentationDetents([.medium, .large])` + 中身フィット) を Flutter で作る必要があった。Flutter SDK には detent 機構が無い (`CupertinoSheetRoute` は `topGap` 固定、`DraggableScrollableSheet` は子の高さを知らない)。

## What

`smooth_sheets` の `ModalSheetRoute` + `Sheet` に、自前の `SheetSnapGrid` を渡すと全部そろう。

```dart
class MediumOffset implements SheetOffset {          // min(中身, 画面の半分)
  const MediumOffset();
  double resolve(ViewportLayout m) =>
      math.min(m.contentSize.height + m.contentBaseline, m.viewportSize.height * 0.5);
  bool operator ==(Object o) => o is MediumOffset;
  int get hashCode => (MediumOffset).hashCode;
}
class DetentGrid implements SheetSnapGrid {
  const DetentGrid();
  static const medium = MediumOffset(), large = SheetOffset(1);
  static bool fits(ViewportLayout l) =>
      l.contentSize.height + l.contentBaseline <= l.viewportSize.height * 0.5;
  (SheetOffset, SheetOffset) getBoundaries(ViewportLayout l) =>
      fits(l) ? (medium, medium) : (medium, large);
  SheetOffset getSnapOffset(ViewportLayout l, double o, double v) => fits(l)
      ? medium : const SheetSnapGrid(snaps: [medium, large]).getSnapOffset(l, o, v);
}
// route: ModalSheetRoute(swipeDismissible: true, barrierColor: black54,
//   viewportBuilder: (c, s) => SheetViewport(padding: EdgeInsets.only(top: viewPadding.top + 10), child: s),
//   builder: (_) => Sheet(initialOffset: DetentGrid.medium, snapGrid: const DetentGrid(),
//     scrollConfiguration: const SheetScrollConfiguration(),
//     decoration: SheetDecorationBuilder(size: SheetSize.stretch, builder: (c, child) => Material(...)),
//     child: Column(min, [grabber, header, Flexible(SingleChildScrollView(primary: true, ...))])))
```

実走で確かめたこと (400×800、viewPadding top 50):
- 生の `SizedBox(300)` → 上端 500 (fit)。中身 400 → min==max (1 段)、401 → 2 段
- 長い中身 → 上端 400 (medium)、`animateTo(SheetOffset(1))` / 上フリック → 60 (= 50 + 10)
- medium で本文を上へドラッグ → 中身はスクロールせずシートが動く。large で上へ → 中身がスクロール。large から下フリック → medium (閉じない)
- 外タップ・下ドラッグで閉じる。前の route の幅は 1.0 倍 (縮まない)。バリアは `0x8A000000`
- **読み込みで中身が 100 → 1500 に伸びても medium (400) で止まる** — 待機の目標を `SheetOffset(1)` でなく `MediumOffset` にしているから

## Why

- `SheetSnapGrid.getBoundaries` / `getSnapOffset` は**レイアウトのたびに**中身の高さ込みで呼ばれる (`SheetModel.applyNewLayout`)。なので「fit か 2 段か」を state で持たず grid の中で決められる。Atender (SwiftUI) のように中身を測って detent を差し替える 2 パスが要らない
- 待機中は `IdleSheetActivity(targetOffset)` が目標の `SheetOffset` を毎レイアウト resolve し直す。fit の目標を `SheetOffset(1)` (中身の全高) にすると、中身が伸びたとき全高に追従して large へ飛ぶ。`min(中身, 半分)` を目標にすると medium で止まる
- `SheetScrollable` (Sheet が `scrollConfiguration` 指定時に自動で挟む) は「シートが maxOffset 未満ならシートを動かし、maxOffset からは中身をスクロール、中身が最上部なら下ドラッグでシートを下げる」を実装している (`_applyScrollOffset`)。iOS の medium → large → scroll がそのまま出る

## How to apply

- **バージョンは 1.2.1 に pin する (2026-10 時点)**。1.3.0 は `package:flutter/material.dart` → `package:material_ui` (Material の独立コピー、238 ファイル) に import を替えただけで、ロジックは 1.2.1 と同一 (tarball の diff で import 行だけ)。1.3.0 の `Theme.of` はアプリの `MaterialApp` のテーマを見ず、`material_ui` + `cupertino_ui` + シェーダ資産が依存に入る。アプリ自体が `material_ui` に移るまでは 1.2.1
- 中身は `SingleChildScrollView(primary: true)` で Sheet の `PrimaryScrollController` に載せる。テストでスクロール量を読むときは `PrimaryScrollController.of(本文)` では取れない (primary:true の内側は `none` に差し替わる) — `ScrollableState.position.pixels` を読む
- 面 (Material) は `SheetDecorationBuilder(size: SheetSize.stretch, ...)` で自分で組む。`MaterialSheetDecoration` は色を省くと `Theme.of(...).colorScheme.surface` を引く (1.3.0 では別系統の Theme)
- `SheetViewport.padding.top` が large の上の隙間。`viewInsets` はシートの位置に使われない (キーボードでシートは動かない)。入力欄を置くなら `Sheet(padding: bottom: viewInsets.bottom)`
- シートの中身の下余白は `MediaQuery.viewPaddingOf(context).bottom` で取る。`padding.bottom` はキーボードが出ると 0 になり、中身の高さで止まっている fit / large が 34pt 下がる (実測 579→613)。横向きのノッチは `viewPadding.left/right` を見出し・✕・本文の内側の余白に足す (面は全幅)
- large を一度選んだ後に中身が縮むと、目標 `SheetOffset(1)` が残るので見た目は fit でも、触らずに伸びれば large に戻る (= 利用者の large を保持)。fit に見えている間に触って離すと snap が medium を返し、以後は medium
- 下へのドラッグは最下段 detent を越えた分が route の閉じる動きになり、large から 1 ジェスチャで閉じられる。離した時、下向き速度が残っていれば「速度 > 画面高 × 2 /秒」だけで判定 (距離は見ない)、止めてから離せば「見えている高さ < 中身 × 0.3」で判定。テストでは `timedDrag` は速度が残る側になるので、距離の判定を見たいときは `startGesture` で動かして 300 ms 止めてから離す
- 当たり判定: 描画だけの子 (`CustomPaint` / 子なし `SizedBox`) を包む `GestureDetector` は `HitTestBehavior.opaque` にしないとタップが素通りする
- `CupertinoAlertDialog` を `MaterialApp` の中で出すと、既定ボタンの色は Material の `colorScheme.primary` (MaterialBasedCupertinoThemeData) になる。純正の青にするには `CupertinoTheme(data: CupertinoThemeData(brightness: dark, primaryColor: CupertinoColors.systemBlue))` で包む (実測: 上書きなし `#C9CDD6` → あり `#0A84FF`、破壊的 `#FF453A`、`isDefaultAction` は w600、`showCupertinoDialog` は既定で外タップで閉じない)
- 関連: [[swiftui-bottomsheet-content-fit-detent]] (SwiftUI 版)、[[../gotcha/flutter-cupertino-sheet-drag-handle-dropped-and-invisible-dark]]
