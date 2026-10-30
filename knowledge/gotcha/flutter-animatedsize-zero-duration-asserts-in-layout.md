---
title: AnimatedSize を Duration.zero にすると、サイズが変わる build で debug assertion (RenderAnimatedSize mutated in its own performLayout)
category: gotcha
tags: [flutter, animatedsize, disableAnimations, accessibility, reduce-motion, review]
created: 2026-10-31
project: bloom
sources: [.designs/20261031-beacon-close-prompt.md §2-2 (disableAnimations なら 0 ms), app/test/reviewer_close_prompt/s3_test.dart (GC-S3-8)]
---

## Context

bloom のクローズ促し (S3 の `ClosePromptBar`) は「出る / 消えるは 240 ms の AnimatedSize + AnimatedOpacity、`MediaQuery.disableAnimations` なら 0 ms」と設計された。実装は `duration: reduced ? Duration.zero : 240ms` を `AnimatedSize` に渡している。

## What

`disableAnimations: true` の状態で子のサイズが変わる (行が出る / 消える) と、debug / テストでは次の assertion が連続して出る。

- `A RenderAnimatedSize was mutated in its own performLayout.` (`RenderAnimatedSize._restartAnimation` → `AnimationController.forward` → `notifyListeners` → `markNeedsLayout` が layout 中に走る)
- 続けて `AnimatedOpacity` 側のコントローラでも同種の例外 (テストでは "Multiple exceptions (4)")

release ではこの assert は外れるので端末で落ちはしない。ただし dev / TestFlight の debug 系ビルド、widget テスト (`accessibilityFeaturesTestValue = FakeAccessibilityFeatures(disableAnimations: true)`) では必ず赤になる。

## Why

`AnimatedSize` は duration 0 でも `forward()` を layout の中で呼び、同期的に listener (= `markNeedsLayout`) が走る。0 ms のとき Flutter が自動で素通しにしてくれるわけではない。

## How to apply

- 設計 doc で「Reduce Motion なら 0 ms」と書くときは **「AnimatedSize / AnimatedContainer の duration を 0 にする」と書かず**、「`disableAnimationsOf(context)` なら AnimatedSize を使わず、子を直接 (`visible ? child : SizedBox.shrink()`) 出す」と書く。
- Reviewer: 動きの設計 (出入りのアニメ) には `disableAnimations: true` の 1 本 + 通常時の陽性対照 (2 フレーム後はまだ途中) を必ず入れる。`tester.takeException()` が複数だと "Multiple exceptions" になるので、値の assert と例外の assert は別テストに割る。
