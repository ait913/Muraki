---
title: dev の .env が Vitest に漏れて .env.test を上書きする — 「.env を直す」は誤った処方
category: gotcha
tags: [vitest, dotenv, env, testing, atender, known-failures]
created: 2026-07-17
project: atender
sources:
  - "atender feature/version-management レビュー (2026-07-17 実測)"
  - "atender .knowledge/known-failures.md 環境依存節"
  - "Muraki/knowledge/role/reviewer.md note 27"
---

## Context

atender の `apps/api` は app が import 時に dotenv で `.env` を読む構成のため、
Vitest 実行時に **dev 用 `.env` (gitignore) が `.env.test` を上書きする**。
2026-07-14 に一度踏み (role note 27)、2026-07-17 に**同じ穴を再度踏んだ**。

## What

漏れる変数は 1 つではなく **3 つ**あり、合計 **5 件**のテストが落ちる:

| 変数 | dev `.env` | `.env.test` | 落ちるテスト |
|---|---|---|---|
| `BETTER_AUTH_COOKIE_DOMAIN` | `localhost` | `.appily.run` | `auth [§8 #7]` Set-Cookie 契約 |
| `PUBLIC_WEB_URL` | `http://localhost:5173` | `https://atender.appily.run` | `cors-cookie [§8 #70]` Allow-Origin が null |
| `BETTER_AUTH_TRUSTED_ORIGINS` | `...,atender://` (truncate) | `...,atender://auth` | `ios-api §8.4` native/callback 3 件 |

**★ 旧台帳の処方「`.env` を `.env.test` の値に直す」は誤り。**
上 2 つの dev 値 (`localhost` / `localhost:5173`) は **dev としては正しい値**であり、
直すと今度は**ローカル開発が壊れる**。真の欠陥は値ではなく **`.env` が漏れること自体**。

(3 つ目の `atender://` truncate だけは dev としても真のバグ。iOS の callback は `atender://auth`。)

## Why

「テストを通すために dev 設定を書き換える」と、テストと開発環境が
**同時に成立しない**構成になる。落ちているのは実装でも `.env` の値でもなく、
**テストプロセスが dev 設定を読んでしまう配線**。

この 5 件は「CORS が壊れた」「認証が壊れた」の顔をして現れるので、
新 feature の regression と誤帰属しやすい (実際 `cors-cookie §8 #70` は
`clientVersionGuard` を入れた直後に現れたように見えた)。

## How to apply

- **env 由来の一括失敗はコードでなく「ロードされている env 実値」をまず疑う** (role note 27)。
  切り分けは失敗テスト内で `console.log(process.env.THAT_VAR)`
- **`.env` を書き換えて検証したら必ずバイト単位で復元する** (`cp` でバックアップ → `diff` で確認)。
  dev 値は正しいので、直した状態で放置しない
- **regression か否かは negative control で決める**: 当該 feature を消した状態
  (`git show <pre-feature>:src/index.ts > src/index.ts`) で同じテストを回す。
  同一に落ちれば feature 起因ではない
- **恒久対策 (未実施・要判断)**: Vitest 側で dev `.env` を読ませない
  (vitest config で dotenv の読み込み元を `.env.test` に固定する等)
