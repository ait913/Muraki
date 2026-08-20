---
title: Dio の既定 validateStatus が独自エラー封筒への変換より先に例外を投げる
category: gotcha
tags: [dio, flutter, error-handling, api-client, testing]
created: 2026-08-21
project: bloom
sources: [projects/bloom/.designs/20260820-phase1-tech-foundation.md §6-1, projects/bloom/app/test/reviewer_p3/beacon_state_machine_test.dart, projects/bloom/app/test/reviewer_p3/post_multipart_test.dart]
---

## Context
Bloom (Flutter + Dio) の `ApiClient` は、サーバーの共通エラー封筒
(`{"error":{"code":"...","message":"..."}}`) を `ApiException(code, message,
statusCode)` に変換して呼び出し元へそのまま投げる設計 (`ApiException` クラスの
doc コメントが `createPost`/`BeaconActions` など広範囲から参照されている)。
P3 レビューで、Dio のカスタム `HttpClientAdapter` を使い 409/403 応答を返す
負のコントロール的テストを書いたところ、`ApiException` ではなく生の
`DioException [bad response]` がそのまま漏れることが判明した。

## What
Dio は `RequestOptions.validateStatus` の既定実装で「ステータス < 300 のみ成功」
とみなす。これを上書きしていない状態で非 2xx を返すと、**アダプタが返した
`ResponseBody` を Dio 自身が正常応答として扱う前に `DioException
(type: badResponse)` を投げてしまう**。エラー封筒を解析して `ApiException` に
変換するロジックが interceptor 等にあっても、それが実行される前に例外が
呼び出し元まで抜けてしまえば、そのロジックは事実上デッドコードになる。
P2b 時点の既存テスト (`f1_payload_test.dart` 等) は成功応答 (200/201) しか
検証していなかったため、この欠落は P3 で意図的にエラー応答を注入するまで
気づかれなかった。

## Why
- Dio の `validateStatus` は「ステータスコードで成功/失敗を判定する層」であり、
  「レスポンスボディをアプリ独自のエラー形式に変換する層」より**手前**にある。
  後者を効かせたいなら、前者を無効化 (`validateStatus: (status) => true` 等)
  してから自前でステータス判定 + 変換する必要がある。
- 成功応答だけを検証するテスト (dio アダプタ capture パターン) は、この種の
  「エラー経路だけデッドコード」を検出できない。負のコントロール (意図的に
  エラー応答を注入する) を打たない限り、実装が設計の doc コメントどおりに
  動いているという確認にはならない。

## How to apply
- **Architect**: API クライアントの設計docに「エラー応答の変換」を書くときは、
  「HTTP クライアントライブラリの成功/失敗判定をどう無効化するか」まで
  具体化する (validateStatus の扱いを明記するか、Developer 任せにしない)。
- **Developer**: Dio ベースの ApiClient を書くときは `validateStatus` を
  広く許容 (例: `status != null`) にした上で、レスポンス受信後に自前で
  ステータスを判定して `ApiException` を throw する。`onError` interceptor で
  変換する場合も、呼び出し元まで `ApiException` そのものが (`DioException` に
  包まれた `.error` フィールドではなく) throw される経路になっているかを
  実際にエラー応答を注入して確認する。
- **Reviewer**: 成功応答だけの dio-capture テストで満足しない。エラーコード
  ごとに UI 分岐がある設計 (409/403/410 等) では、少なくとも 1 本は
  意図的に非 2xx を返す負のコントロールを書き、`ApiException` として
  拾えるかを確認する。拾えなければ、その API を使う全ての呼び出し元の
  エラー分岐が机上の空論になっている可能性がある (影響範囲を doc コメントの
  参照元から機械的に洗い出す)。
