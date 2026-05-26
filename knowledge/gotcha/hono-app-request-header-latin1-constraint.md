---
title: Hono の app.request() はテスト経路で HTTP ヘッダ値を Latin-1 (ByteString) に制限する
category: gotcha
project: global
tags: [hono, vitest, testing, http, latin-1, better-auth, encoding]
created: 2026-05-26
sources:
  - node_modules/hono/dist/hono-base.js:350 (Hono.request → ByteString)
  - omatase-demo-mvp Reviewer run (2026-05-26)
  - 設計 §7.1.1 「`x-guest-name: たんり` → `user.name="たんり"`」
---

## Context

better-auth + Hono + Vitest で「匿名サインインに日本語名を `x-guest-name` ヘッダで渡す」テストを書こうとすると、

```ts
await app.request("/api/auth/sign-in/anonymous", {
  method: "POST",
  headers: { "x-guest-name": "たんり" }, // ← ここで TypeError
});
```

`TypeError: Cannot convert argument to a ByteString because the character at index 0 has a value of 12507 which is greater than 255.` で失敗する。

実 HTTP 経由 (Node の fetch / curl 等) では UTF-8 ヘッダが通る場合があるが、**Hono の `app.request()` は Fetch API の Headers コンストラクタを経由するため、ヘッダ値が Latin-1 範囲外だと例外**。

## What

設計 doc に「日本語名をヘッダで渡す」と書くと、テスト経路で 2 通りの問題が同時に起きる:

1. **Hono 側**: `app.request()` が Latin-1 制約で TypeError → そもそも fetch が走らない
2. **実装側 (better-auth `generateName` 等)**: ヘッダから raw bytes を取り出して使う設計だと、テストが percent-encode で送った場合に DB に `%E3%81%9F%E3%82%93%E3%82%8A` が保存される

両方を回避するには:

- テスト helper で `encodeURIComponent` 経由で送る → app.request の例外は回避
- assert は「raw or percent-decoded どちらでもマッチ」で受ける `expectNameMatches`-like ヘルパで両対応

```ts
function isLatin1(s: string): boolean {
  for (let i = 0; i < s.length; i++) if (s.charCodeAt(i) > 0xff) return false;
  return true;
}
function encHeader(s: string): string {
  return isLatin1(s) ? s : encodeURIComponent(s);
}
function nameMatches(actual: string, expected: string): boolean {
  if (actual === expected) return true;
  try { return decodeURIComponent(actual) === expected; } catch { return false; }
}
```

## Why

- `app.request()` の内部は `new Headers(init.headers)` を呼ぶ。Fetch 標準は ByteString (Latin-1) を要求するので、コードポイント 255 超は throw
- 本番 Node http server (`@hono/node-server`) は **UTF-8 をそのまま受け付ける** ことが多い。テストだけ throw する → デモは動くがテストが書けない、という事故が起きる
- better-auth の `anonymous` plugin `generateName(ctx)` は `ctx.request?.headers.get(...)` の戻り値をそのまま `slice(0, 80)` する設計なので、percent-encode された文字列がそのまま user.name に入る
- 設計 doc に「日本語例」を書くと Reviewer も Developer も「raw 日本語で書ける」と誤認しやすい

## How to apply

### Architect (設計時)

- ヘッダで日本語を渡す API を設計する時は、**「ヘッダは percent-encoded UTF-8 として送り、サーバ側で `decodeURIComponent` する」** 規約を明記する
- もしくは「日本語は body (JSON) で渡す」設計に変える (本番でも安全)
- 例示で「`x-guest-name: たんり`」のような raw 文字列を出さない (混乱の元)

### Reviewer (テスト時)

- helper (`loginAsGuest` 等) は `encodeURIComponent` で送る
- assertion は raw / decoded 両対応 helper を使う (`nameMatches` 等)
- 設計通りの厳密検証が必要なら、`app.request()` ではなく **実 HTTP** (`@hono/node-server` の `serve()` を listen して `fetch()` で叩く) に切り替える。MVP では不要

### Developer (実装時)

- 設計が percent-encoded UTF-8 を規定するなら `decodeURIComponent(headers.get("x-guest-name") ?? "")` する
- 規約が無いなら raw bytes (Latin-1) 解釈に留めて Reviewer 側で adapt させる

## 関連

- [[gotcha/better-auth-test-cookie-must-match-hono-signed-format]]
- [[gotcha/design-must-specify-app-export-path-for-tests]]
