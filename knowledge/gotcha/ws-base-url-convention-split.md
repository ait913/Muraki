---
title: 同じ「WS のベース URL」で /ws を含む規約と含まない規約が混在すると黙って死ぬ
category: gotcha
project: omatase
tags: [websocket, env, configuration, realtime]
created: 2026-07-29
sources: [omatase 2026-07-29 ブラウザ実機で発見]
---

## Context

WS の接続先を env で渡す構成はどこにでもある。omatase では 3 箇所が同じ「WS のベース URL」を持っていたが、**パスを含む/含まないの規約が逆**だった:

| 変数 | 使う側のコード | `/ws` を |
|---|---|---|
| `NEXT_PUBLIC_WS_BASE` | web: `` `${base}/ws?token=...` `` と**付ける** | 含めない |
| `EXPO_PUBLIC_WS_BASE` | mobile: `new URL(config.wsBase)` で**そのまま** | 含める |
| `API_WS_BASE` | backend: join 応答の `ws_url` に**そのまま**載せる | 含める |

3 つのうち 2 つが「含める」なので、env を設定する人間は自然と `/ws` を付ける。web だけがそれを二重にする。

## What

`wss://api.example.org/ws` を web の env に入れると接続先が `wss://api.example.org/ws/ws` になり、**handshake が 404 で落ちる**。

壊れ方が最悪:

- **画面は完全に正常に出る**。REST は別 env (`NEXT_PUBLIC_API_BASE`) なので初期スナップショットは取れ、地図もメンバー一覧も描画される
- 死ぬのは**リアルタイム部分だけ** — presence が全員 `offline` のまま、位置も相手のステータスも一生更新されない
- サーバーログにも目立つエラーが出ない (404 を返しただけ)
- 気付けるのはブラウザの console か、「なんか位置が動かない」というユーザー報告

CI もデプロイも smoke も全部緑のまま通る。ビルド時埋め込み (`NEXT_PUBLIC_*`) なので、env を直しても**再ビルドしないと直らない**点も混乱を増やす。

## Why

「ベース URL」という名前が、パスをどこまで含むかを規定しない。書いた人はそれぞれのファイル内では一貫していて、**跨いで見た人だけが矛盾に気付く**。型でも lint でも検出できない (どちらも `string`)。

さらに WS は「繋がらなくてもアプリが動いてしまう」ので、フェイルファストしない。REST の base URL を間違えれば即座に全画面が壊れて気付くが、WS は静かに劣化する。

## How to apply

- **同じ概念の値は、規約を 1 つに決めて表で正典化する**。omatase では `CLAUDE.md` に上の表を置いた。名前が同じで意味が違う値を放置しない
- **URL 組み立ては冪等にする**。末尾の `/ws` を吸収してから付ける:

  ```ts
  const base = wsBase.replace(/\/+$/, "").replace(/\/ws$/, "");
  return `${base}/ws?token=${encodeURIComponent(token)}`;
  ```

  厳密に弾いて設定ミスを早期に気付かせる、という考え方もあるが、**この失敗はサイレントに劣化する**ので吸収する方が実害が小さい。吸収した上で正典の形をドキュメントに書く。
- **検証は必ずブラウザで接続状態まで見る**。ユニットテストは env の値を知らないので絶対に見つからない。接続状態 (`open`/`closed`) と presence が画面に出ているなら、そこが最短の確認点
- リアルタイム機能には**接続状態を UI に出す**。omatase は出していたので、a11y スナップショット 1 回で `closed` と分かった

関連: [[next-public-env-needs-dockerfile-arg]] (ビルド時埋め込みなので env 修正には再ビルドが要る)
