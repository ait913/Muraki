---
title: Riverpod Notifier の state を == 無しで copyWith すると、select なしで watch する全 provider が作り直されて REST を一式再取得する (bloom のグループ画面が重い原因)
category: gotcha
project: global
tags: [riverpod, flutter, performance, provider, rate-limit, bloom]
created: 2026-10-19
sources:
  - sessions/2026-10-16-4aab8def.md (項目 89)
  - projects/bloom app/lib/state/app_state.dart (markGroupRead / demoProvider)
  - riverpod 3.4.2 lib/src/core/element.dart defaultUpdateShouldNotify (previous != next)
---

## Context

bloom は demo モード用の `demoProvider` (`Notifier<DemoState>`) を、データ系の provider (groups / groupDetail×N / groupMap×N / posts×N / blocks / places …、34 箇所) が `ref.watch(demoProvider)` で丸ごと watch していた。`DemoState` は `operator ==` を持たない。

## What

- riverpod 3 の `defaultUpdateShouldNotify` は `previous != next`。`==` が無い class を `copyWith` で置き換えると、値が同じでも毎回「変わった」扱いで全 watcher が rebuild する。
- bloom では「グループを開いた」印 (`markGroupRead`) がライブ時にも `demoProvider.markRead(gid)` を呼んでいた → グループを 1 回開くたびに 34 provider が作り直され、REST を一式 (groups / 各グループの detail・map・posts / blocks / activity / avatar) 取り直す。本番ログで 1 ユーザーが 1 分に 320 要求、`GET /v1/groups/{gid}` 119 回、429 が 226 件。サーバー側の書き込みも WS も無い分で起きる = 純粋にクライアントの構造。
- 0.2.2 でも同じ動線だったが安かった。0.2.3 で 1 回の再取得が重くなった (端末側集計をメインスレッドで・投稿の復号・MapLibre の作り直し) ので「異様に重い」として表面化した。

## Why

- 症状は「画面遷移が重い」「429 が出る」で、原因の provider には何の例外も出ない。access log で「1 ユーザーの同一 GET が秒間 10 回以上、サーバー側の書き込み・WS 配信ゼロ」を見つけて初めてクライアント内部の fan-out と分かった。
- `ref.watch(x)` の「x が変わった」は値でなく `!=` の結果。state class の等価性と watch の粒度 (`select`) はセットで設計しないと、無関係な書き込みが全体の再取得になる。

## How to apply

- Notifier の state class は値等価 (`==` / `hashCode`、または freezed / `equatable`) を持たせるか、watch 側を `ref.watch(p.select((s) => s.seeded))` のように必要な射影に絞る。両方やるのが安全。
- 「印を付ける」「既読にする」類の軽い書き込みを、データ provider が watch している state に入れない (別の小さな provider に分ける)。
- 疑ったら access log で `(minute, user) → GET 回数` を集計し、同じ分にサーバー側の書き込み・WS があるかを見る。無ければクライアントの fan-out。bloom のログは JSON (`msg=access`、`path` は `{gid}` に正規化済み) なので python で 10 行で出る。
- Crashlytics には出ない。429 (`RATE_LIMITED`) の非致命エラーだけが手がかりになる。
