---
title: Image の key を変えるだけの「再読込」は、失敗した ImageStream を ImageCache の live image から再利用して再取得しない
category: gotcha
tags: [flutter, imagecache, image-provider, retry, bloom]
created: 2026-10-16
project: bloom
sources: [bloom thumb-rate-limit Reviewer (GB9/GB10), .designs/20261016-thumbnail-rate-limit-and-glow.md]
---

## Context
`Image(key: ValueKey((id, gen)), image: customProvider)` で、失敗後に `gen` を上げて再構築すれば再取得されると設計した (bloom の ThumbGlow / postThumbWidget)。同じ `ImageProvider` が `==` で共有されている (前景と影)。

## What
`gen` が上がっても HTTP が再発行されない。widget テストで観測: 失敗直後 `imageCache.liveImageCount == 1`、3 秒後の再読込で取得は 1 回のまま (`imageCache.clearLiveImages()` + `clear()` を挟むと 2 回になり画像も出る)。

## Why
key が変わると新しい Element が先に build され、古い State の dispose は後。新 `Image` の resolve は `ImageCache.putIfAbsent` で、古い (失敗した) completer がまだ `_liveImages` に居るため再利用し、保存済みのエラーを新しいリスナーへ再生する。失敗した画像は pending からは外れるが live からは「最後のリスナーが外れる」まで残る。

## How to apply
- 「key を変えて再構築」では足りない。再読込の前に `provider.evict()` (`ImageProvider.evict` は live も消す) か `imageCache.evict(key)` を呼ぶ。`AuthedNetworkImage` が `NetworkImage(...).evict()` してから `_reloadKey++` しているのはこのため。
- 再読込のテストは「状態 (世代) が進んだ」でなく「取得回数が増えた」を assert する。fake adapter の到達回数で見る。
- 失敗が `ImageProvider` 内部の Future の例外 (自前 provider) でも同じ。
