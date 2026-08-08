---
title: expo-router の replace は「新規エントリ置換 = 再 mount」であり params 更新ではない
category: gotcha
project: omatase
tags: [expo-router, react-navigation, navigation, stack, remount, params]
created: 2026-08-08
sources:
  - omatase build 11 のハブ⇄/now 無限ループ (実機) と積み上がり (S1-S8 監査)
  - node_modules/expo-router/build/react-navigation/routers/StackRouter.js (REPLACE 実装)
model-era: fable-5
---

## Context

omatase mobile (expo-router / 単一 Stack) で「query param を消すためだけの `router.replace(同一 pathname)`」を使ったところ、実機で ハブ⇄進行ページの無限往復と、戻っても同種画面が積まれ続ける症状が出た。

## What

- expo-router の `router.replace` は React Navigation の `REPLACE` を root dispatch する。**`source` が付かないため常にフォーカス中の最上段 1 枚を「新しい key の新規エントリ」で差し替える**。同一 pathname でも params 差分の更新ではない
- 帰結 1: **route コンポーネントは再 mount され、`useRef`/`useState` は全部リセットされる**。「mount 時 1 回だけ」のガード ref は replace のたびに無効化される — 「param を消す replace」がガード自体を消し、判定が再発火してループになった
- 帰結 2: replace は下のエントリを消さない。**push で開いた画面から「replace で親へ戻る」と、下に残った親の上へ同種画面が 1 枚積み増される** (戻るたびにイベントページが出てくる、の正体)
- 帰結 3: deep link (NAVIGATE) は「最上段が同名 route のときだけ再利用、それ以外 push」。cold 起動では anchor (`unstable_settings.initialRouteName`) が無い限りホームは下に積まれない

## Why

Next.js の `router.replace` (同一ページならコンポーネント維持・searchParams だけ更新) と名前が同じで、同じ意味論だと思い込みやすい。web で正しいパターンを mobile に移植すると壊れる。

## How to apply

- **「param を消すためだけの replace」を mobile でやらない**。消せない前提で設計する (mobile は URL が見えないので、残しても実害がないことが多い)
- 「一度だけ実行」のガードを navigation 越しに保ちたいなら、instance ref でなく**スタックに残る instance そのもの**を使う (例: 着地は replace でなく **push** にして、判定済みの親 instance を下に残す)
- 子画面から親へ戻るのは replace でなく `router.back()` / `router.dismissTo(href)` (スタックを掘って既存エントリへ pop、無ければ replace)
- cold deep link にホーム脱出口を作る: ‹ は `canGoBack() ? back() : replace('/')`
