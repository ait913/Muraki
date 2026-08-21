---
title: coder/websocket は呼び手の ctx timeout でも接続そのものを閉じる
category: gotcha
tags: [go, websocket, coder-websocket, testing, reviewer]
created: 2026-08-21
project: bloom
sources: [server/internal/httpapi/reviewer_ws_test.go, .designs/20260820-phase1-tech-foundation.md §8]
---

## Context

bloom P3c の WS (`coder/websocket` v1.8.15) を reviewer がブラックボックス probe するとき、
「短い `context.WithTimeout` を都度張り直して `conn.Read(ctx)` をポーリングする」ハーネスを書いた。
access token の exp を 1s/3s/5s/10s と変えて close code 4001 のタイミングを測ろうとしたところ、
**exp の長さに関係なく毎回 ~300ms (自分が設定した ctx timeout の長さ) で `use of closed network
connection` エラーが発生**し、最初は「サーバー側が短い周期で token freshness を再チェックしてい
る」ように見えた (偽の観測)。

## What

`coder/websocket` の `Conn` は godoc に明記の契約として「**メソッドが何らかのエラーを返したら
(呼び手が渡した `ctx` の timeout/cancel を含めて) 接続そのものを閉じる**」。つまり
`conn.Read(shortCtx)` が `shortCtx` の deadline で timeout すると、それはサーバー側の挙動と無関係に
**クライアント側の `Read` 自身が接続を破壊**する。短命 ctx で `Read` をリトライするループは、
テストしたい対象 (サーバーが本当に close するか) より先に自分の ctx が接続を殺してしまう。

## Why

ライブラリの設計思想が「エラーは全部 fatal (再試行不可)」であるため。生の `net.Conn` の
`SetReadDeadline` のような「timeout はエラーだが接続は生きている」を期待すると誤検出する。

## How to apply

- WS の接続 lifecycle (close code / 認可失効等) を検証するときは、**1 コネクションにつき 1 回の
  `Read` を、十分に長い ctx (テストが待ちたい最大時間そのもの) で block させる**。短い ctx でのポー
  リングループは書かない。
- 複数メッセージを順番に受け取りたい場合も、成功した `Read` の後に**新しい**十分に長い ctx で次の
  `Read` を呼ぶ (前の呼び出しの ctx を使い回したり、cancel 済みの ctx を渡したりしない)。
- 「メッセージが届かないこと」を確認する負のコントロールは、最後に 1 回だけ短命 ctx で `Read` を呼
  び timeout を確認する (その後そのコネクションは使い捨てる前提)。
- 同族の罠: `os.Pipe` で `os.Stdout`/`os.Stderr` を差し替えてログ捕捉するテストで、**接続の
  access ログは handler が return (= 切断) した瞬間にしか出ない**。capture window 内で明示的に
  `conn.Close()` しないと、window の外 (t.Cleanup 等) でログが出て検証が空振りする
  (vacuous green)。捕捉直後に「期待するログの一部が実際に含まれているか」も assert して検知する。
