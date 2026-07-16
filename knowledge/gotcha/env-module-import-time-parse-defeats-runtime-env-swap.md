---
title: env モジュールの import 時パースが実行時 env 差し替えテストを無効化する
category: gotcha
project: atender
tags: [testing, env, vitest, better-auth, module-cache]
created: 2026-07-14
sources:
  - atender feature/login-auth-revamp Reviewer (2026-07-14)
---

## Context

atender `apps/api` の `src/env.ts` は `EnvSchema.parse(process.env)` を **モジュール import 時に一度だけ**実行し、以後 `env` オブジェクトはその時点の値で固定される。設計doc は Apple provider の env 分岐 (A1-A6) を「`process.env.APPLE_* を set → resetAuth() → getAuth()`」で検証せよと指示したが、この手順では検証できない分岐がある。

## What

`getAppleProviderConfig()` は `env`(= import 時パース結果)を読む。テストが**実行時に** `process.env.APPLE_CLIENT_ID = ...` を代入して `resetAuth()` を呼んでも、`env` オブジェクトは import 時のスナップショットのままで更新されない。テスト環境の `.env.test` / `setup.ts` に APPLE_* が無いため、`env.APPLE_*` は常に undefined → provider は常に null → `POST /sign-in/social {provider:"apple"}` は常に 404。

結果、「apple env 未設定 → 404」テストは通るが、「apple env 設定 → provider 登録 (非404)」テストは**実装が正しくても偽 fail** する。

## Why

Node の ESM/CJS モジュールキャッシュ + 「env を一度パースして固定するパターン」の組合せ。`resetAuth()` は better-auth インスタンスを作り直すが、その入力である `env` は再パースされない。同型の罠は trustedOrigins など env 由来の全設定に及ぶ。

## How to apply

- **env 由来の分岐は「プロセス起動前に env を投入」して検証する。** 別プロセス (専用 test ファイルを別 env で起動 / `vitest` を `APPLE_*=... vitest run xxx.test.ts` で) か、`setup.ts` で投入する。同一プロセス内の runtime 代入 + resetAuth では届かない。
- atender では boot-probe (APPLE_* を export した状態で 1 本だけ実行) で「provider 登録時は 401 INVALID_TOKEN が返る (404 でない)」を確認し、実装の正しさを実証した。
- ブラインド生成テストで env 分岐を書くときは、**未 export の内部関数 (getAppleProviderConfig 等) の内部値を直接 assert せず、HTTP 観測に寄せる**。ただし HTTP 観測でも env が起動時に無ければ観測不能なので、「env 未設定側 (404)」だけを in-process で検証し、「env 設定側」は boot-time 実行に回す。
- Architect への還元: 設計doc の「env 差し替えは process.env set → resetAuth」という手順は、env を import 時パースで固定する構成では不正確。設計に「env 由来分岐はプロセス起動時投入で検証」と明記すべき。
