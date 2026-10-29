---
title: better-auth の送信コールバック (sendMagicLink 等) を外部メール API に繋ぐ — fetch で薄く包み、失敗は APIError に API の封筒を詰めて投げる
category: pattern
tags: [better-auth, magic-link, email-sending, error-envelope, fetch-mock, vitest, ais-mail]
created: 2026-10-30
project: global
sources:
  - projects/atender/.designs/20261030-magic-link-mail-via-ais-mail.md
  - better-auth 1.6.33 dist/plugins/magic-link/index.mjs, dist/api/index.mjs (onError)
---

## Context

atender の Magic Link を Resend SDK から AIS Mail (`POST /api/v1/send`) に移す設計で決めたこと (2026-10-30)。Resend SDK は失敗時に throw せず `{data, error}` を返すため、戻り値を見ていなかった旧実装は送信失敗でも 200 を返していた。

## What

1. **better-auth 1.6.33 の `sendMagicLink` が投げたものの行き先 (scratchpad で `betterAuth` + `memoryAdapter` を実走)**:
   - 素の `Error` → **500、body 空** (Content-Type なし)。Hono の `app.onError` には届かない (better-auth の router が先に握る)
   - `new APIError("INTERNAL_SERVER_ERROR", { code, message })` → 500、body `{code, message}` (better-auth 流の封筒)
   - `new APIError("INTERNAL_SERVER_ERROR", { error: { code, message } })` → 500、body が **そのまま** `{"error":{...}}`。APIError の body 型は `{message?, code?, cause?} & Record<string, any>` なので型も通る
   - どれでも `Verification` 行は残る (有効期限で消えるので無害)。email は小文字化されずにコールバックへ渡る
2. 外部 API は SDK を入れず `fetch` 1 関数 (`sendMail`) で包む: 成功の判定 (HTTP と body の status の両方)、`MailSendError{code, status}` への分類 (相手の error.code / http_error / invalid_response / network_error / timeout)、`AbortSignal.timeout`。メッセージに宛先・本文・トークンを入れない
3. テストは `vi.stubGlobal("fetch", router)` で **相手の base URL で始まる要求だけ** を `vi.fn` に流し、他は本物の fetch へ。`beforeEach` で `mockReset` + 既定実装を入れ直す。既存テストの `vi.spyOn(globalThis, "fetch")` は stub の上に重なり、`restoreAllMocks` で stub に戻る (`stubGlobal` は戻らない)

## Why

- API 全体のエラー封筒 (`{error:{code,message}}`) で返すと、その封筒を読むクライアント (atender iOS の `ErrorResponse`) が無改修でサーバーの文言を表示できる。素の 500 だと「サーバーエラー (HTTP 500)」止まり
- `onAPIError: { throw: true }` で Hono 側に流す手もあるが、全 auth エンドポイントの 4xx まで throw されて 500 に化ける
- モジュール mock (`vi.mock("./lib/mail")`) では HTTP 契約 (URL・ヘッダ・body のキー) がテストされない

## How to apply

- better-auth の送信系コールバック (`sendMagicLink` / `sendVerificationEmail` / `sendResetPassword` / OTP) で外部送信するときは、コールバック内で全例外を捕まえ、ログには分類だけ (`{code, status}`) を出し、`APIError(<status>, { error: { code: "<APP>_SEND_FAILED", message: <ユーザー向け文言> } })` を投げる
- 「受け付けた (queued)」と「確定失敗 (failed)」を同じ 2xx で返す API は、body の status まで見て失敗を拾う (AIS Mail は 202 で `failed` を返す)
- 相手が同期で N 秒待ってから応答する API は、呼び出し側のタイムアウトを N 秒より長くする
