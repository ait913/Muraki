---
title: SwiftUI 横ページャの非可視ページは a11y ツリーに残る (accessibilityHidden も効かない)
category: gotcha
tags: [swiftui, xcuitest, accessibility, paging, ios]
created: 2026-07-30
project: atender
sources:
  - "atender .designs/20260730-ios-unify-calendar-build17.md §3.5"
  - "Reviewer 実測 (build 17, iPhone 16 / iOS 18.2)"
model-era: opus-4.8
---

## Context

atender build 17 で月カレンダーを `ScrollView(.horizontal)` + `LazyHStack(spacing:0)` +
`containerRelativeFrame(.horizontal)` + `.scrollTargetBehavior(.paging)` の横ページャにした
(窓 = 起点月 ±24 ヶ月 = 49 ページ)。Developer は「ページャの a11y ツリー汚染は
`.accessibilityHidden(month != visibleMonth)` で解消済」と申告していた。

## What

**解消していない。** Reviewer が XCUITest で実測 (4/4 再現):

- 1 ヶ月 = 42 セルなのに `app.buttons` に **126 個**の日セルが出る (= 前後 1 ヶ月ぶんが同時に生きている)
- 同じ日番号のボタンが **3〜4 個**ヒットする (`label == "15"` が 3 個)
- 画面外ページのセルは **`{{-345.0, 344.3}, {51.7, 77.0}}`** のように **負の x** を持つ
- `.accessibilityHidden(month != visibleMonth)` は実装に**存在する** (`CalendarScreen.swift:207` に 1 site) が効いていない

二次被害が 2 つある:

1. **XCUITest が画面外セルを掴む。** `app.buttons.matching(...)` は最初にヒットした要素を返すので、
   素直に書くと `Failed to synthesize event: Not hittable: Button, {{-345.0, ...}}` で落ちる。
   実装バグに見えるが、テストが隣のページを触っているだけ。
2. **`XCTAutomationSupport` が SIGSEGV する。** 低頻度で
   `Failed to get matching snapshot: Lost connection to the application` になり、
   クラッシュログの faulting thread は **アプリのフレームをひとつも含まない**:
   `runtime_issue_os_log_fault_callback` →
   `__LIBTRACE_CLIENT_QUARANTINED_DUE_TO_HIGH_LOGGING_VOLUME__` → `-[XCElementSnapshot label]`。
   スナップショット機構が runtime issue の os_log を吐きすぎて quarantine され、その中で落ちている。
   a11y ツリーが肥大した画面ほど出やすい。

## Why

`LazyHStack` はスクロール方向の隣接ページを先読みで materialize する。materialize された
サブツリーは (画面外でも) accessibility hierarchy に載る。`.accessibilityHidden(_:)` を
ページのコンテナに付けても、中身が `Button` (= 自前の accessibility element を作る要素) の
集合だと期待どおりに subtree ごと落ちないケースがある。`TabView(.page)` と違って
`ScrollView` は「表示中のページ」という概念を a11y に伝えない。

VoiceOver では「15日」が 3 回読まれる / スワイプで隣月のセルへ飛ぶ、という形で実害になる。

## How to apply

- **設計**: 横ページャを採るなら a11y 側の分離を設計項目として明記する。
  `.accessibilityHidden` 1 個で足りると仮定しない。代替は
  `.accessibilityElement(children: .contain)` + ページ単位のコンテナ化、
  もしくは可視ページ以外を `EmptyView` に差し替える (先読みを捨てる)。
- **Reviewer**: 「a11y 汚染は直した」という申告は **要素数を数えて**検証する。
  `app.buttons.matching(...).count` が 1 ヶ月ぶん (42) を超えたら汚染。
  `.accessibilityHidden` が**ソースに在る**ことは効いていることの証拠にならない。
- **XCUITest のハーネス**: 日セルのような「ページ内で重複しうる要素」は
  **画面内 (`-1 <= frame.minX`, `frame.maxX <= window.width + 1`) で必ず絞る**。
  絞らないと Not hittable で偽 RED になる。
- **`Lost connection to the application` を実装のクラッシュと即断しない。**
  `~/Library/Logs/DiagnosticReports/<App>-*.ips` を開き、faulting thread に
  アプリのフレームがあるかを見る。`XCTAutomationSupport` / `libsystem_trace` だけなら
  ハーネス由来 (環境依存) で、単独再実行すれば通る。
