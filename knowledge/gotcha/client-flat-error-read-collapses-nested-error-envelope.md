---
title: クライアントの平坦 error 読みが nested error 封筒を全部 unknown に潰す
category: gotcha
tags: [api-client, error-mapping, rest-contract, omatase, web]
created: 2026-07-23
project: omatase
sources: [".designs/20260723-mvp-rest-and-mobile-wiring.md (REST 正典 §共通規約 エラー body)", "apps/web/src/api/client.ts"]
---

## Context
omatase web ゲスト (Next.js) の `api/client.ts` を設計契約だけからテストした。REST 正典
(`20260723-mvp-rest-and-mobile-wiring.md` §共通規約) は**エラー body を nested** と規定:
`{ "error": { "code": "string", "message": "string" } }`。code は機械可読
(`forbidden`/`not_found`/`event_closed`/`invalid_argument`/`conflict`/`unauthorized`)。
web doc も「エラー写像は入口編のエラー body 形」と入口編へ委譲している。

## What
`apiFetch` の非 2xx 写像をブラックボックス probe (fetch を vi.stubGlobal でモックし body 形を変える)
で切り分けたところ、実装は **error body を top-level `{code, message}` として読んでいた**:
- nested `{ error: { code:"forbidden", message } }` → `ApiError.code === "unknown_error"`, `message === ""`
- flat  `{ code:"forbidden", message }`          → `ApiError.code === "forbidden"` (正しく抽出)

つまり**バックエンドが契約どおり nested を返すと、web は全エラーを `unknown_error`/空 message に潰す**。
影響: E5 join の `409 event_closed` → 「終了しました」分岐、`400 invalid_argument` → 名前バリデーション
表示など、**code 分岐する UI が全滅**する (全部 unknown 扱いになり、意味的分岐が死ぬ)。テストは status
(403) しか一致せず code で落ちるので、status だけ assert していたら見逃していた。

## Why
共有 `packages/api-types` (TS) には**成功 DTO の型しか無く、エラー封筒の型が存在しない**。
各クライアントがエラー body の shape を手写しで読むため、nested/flat の取り違えを型で防げない。
Go は nested を出す (正典)、TS クライアントは flat を読む、という**契約の非対称**が生まれた。

## How to apply
- **api client のエラー写像テストは status だけでなく `code`/`message` の実値まで assert する** (status
  一致は封筒 shape 違いを隠す)。
- 帰属は fetch モックの body 形を nested/flat で振る probe 一発で確定する (実装を読まずに済む)。
- **設計時**: 共有型パッケージに `ErrorResponse = { error: { code: string; message: string } }` を定義し、
  全クライアントの写像がこの型を経由するよう強制する (手写し取り違えの根治)。
- **Reviewer チェックリスト**: 「エラー body 形」を規定した REST 契約の PJ では、各クライアントの
  エラー写像が nested を剥がしているかを最初に probe する。
