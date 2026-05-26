---
title: Lucia v3 は 2026-03 で完全 deprecated — 新規 PJ で採用してはならない
category: library
project: global
tags: [auth, lucia, deprecated, session-based]
created: 2026-05-13
sources:
  - https://github.com/lucia-auth/lucia/discussions/1714
  - https://x.com/pilcrowonpaper/status/1847975622087414177
  - https://lucia-auth.com/
  - https://dev.to/gaundergod/lucia-auth-is-getting-deprected-4g7
---

## Context

Web アプリで session-based 認証を組む際、Lucia v3 を選びたくなる場面。session DB + cookie の純度を取る設計で過去人気があったが、**作者 pilcrow が 2024-10 (= 2025年1月以降) に正式 deprecate アナウンス**し、2026-03 で完全停止済み。

## What

- **2024-10-20 (Touri 観測時間軸での 2025-10 相当)**: 作者 pilcrow が X / GitHub Discussion #1714 で「Lucia は学習リソースに転換、ライブラリ機能は deprecate」と宣言
- **2025-03 までに**: v3 の adapter は全て deprecated、NPM パッケージは bug fix のみ
- **2026-03 以降**: 新規メンテナンス停止 (停滞中、最終 publish `lucia@3.2.2` は 2025-06-06、`npm view lucia` で確認)
- **公式トップ ([lucia-auth.com](https://lucia-auth.com/))** は **学習リソース** として残存しているため、知らないと「現役」と誤読する罠あり
- 推奨代替: 作者は **自前実装 (The Copenhagen Book)** + 補助ライブラリ Oslo / Arctic の組合せを推奨。実用的には **better-auth** (1.6.x stable) が後継ポジション

## Why

- 作者の説明: "Database adapters were a significant complexity tax to the library, with adapters limiting the API and making everything clunky and fragile"
- DB スキーマと密結合する設計が継続困難だった
- session-based 認証は「ライブラリでラップする抽象が薄くて済む = 自前実装ガイドで足りる」という哲学転換

## How to apply

- **新規 PJ で Lucia を選ばない**。検索で出てくる Lucia + Next.js / Lucia + Hono のチュートリアルは 2024 以前のもの
- 既存 Lucia 利用 PJ は **better-auth に移行**を検討。スキーマレベルでは user / session / account の概念が似ているが、API は別物なので 1 機能ずつ書き換える
- session-based 純度を取る代替:
  - **better-auth** (1.6.x stable、Magic Link + OAuth + DB session): 実用ファースト
  - **Oslo + Arctic + 自前 cookie 管理**: 学習価値ありだが時間コスト大
- Tally ([ammarmbe/tally](https://github.com/ammarmbe/tally)) のような 2024-2025 製 attendance tracker OSS は Lucia 採用が多い。参考にする時は **認証層だけ切り捨てる** こと
