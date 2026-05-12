---
title: 設計書の error code 表記が「明示」か「例示」か曖昧で実装/テストが食い違う
category: gotcha
tags: [design-doc, error-code, validation, http-status, architect]
created: 2026-05-10
project: global
sources:
  - Muraki/projects/tsunagu/.designs/20260510-mvp-foundation.md
  - Muraki/worktrees/tsunagu-backend (Reviewer 三回目)
---

## Context

設計書 §4.x で API エラーレスポンスを以下のように列挙していた:

```ts
// Errors
// 400 VALIDATION
// 400 FILE_TOO_LARGE
// 415 UNSUPPORTED_MEDIA
// 409 ALREADY_PENDING
```

実装は zod スキーマの size 制約 (`max(5MB)`) で弾いていたため、Tier3 用の
5MB 超ファイルは zod の `VALIDATION` で 400 を返す。設計書に書かれた
`FILE_TOO_LARGE` 専用コードは存在しない。

同様に「403 FORBIDDEN: 通知対象外ユーザー」と書いてあるが、実装側は
通知対象外ユーザーの check より先に「Responder レコードが存在しない」で
判断しており、結果的に 409 ALREADY_RESPONDED が返ってくる (見当違いの
コード) ケースもあった。

## What

設計書のエラー一覧は **「最低限こういうエラーケースがある」** という例示なのか、
**「この code を必ず返せ」** という規約なのかが Architect/Developer/Reviewer で
解釈が割れやすい。

特に Reviewer がテストを書くとき、コードが "FILE_TOO_LARGE" で来ることを
期待してテストを書く → 実装は VALIDATION で返す → fail。
「テストが間違ってる」と片付けると次回の本物のバグを見逃すリスク。

## Why

- 設計時にエラーケースを列挙する作業は「思いつきベース」になりがち
- 実装時は zod など既存ライブラリの仕様にひきずられる
- Reviewer は設計書を **正典** として扱う指示を受けているので、設計書通りの
  code を期待する

## How to apply

### Architect 側

エラー一覧に `// (zod の VALIDATION でも可)` のように **複数許容** を明示するか、
または「この code を返すこと」と **規約として** 書き分ける。

サイズ超過は特に「VALIDATION で来る vs FILE_TOO_LARGE で来る」が分かれやすいので、
最初から `expect([VALIDATION, FILE_TOO_LARGE]).toContain(code)` パターンの
許容を設計に書く方が現実的。

### Reviewer 側

テストで設計書通りの code を期待して fail したら、「設計書曖昧 (YELLOW)」と
「実装バグ (RED)」を切り分ける。MVP 段階で UX に影響しないものは YELLOW で
通し、リリース後に Architect/Developer に返してきれいにする。

### Leader 側

設計書レビュー時に「エラーコードの粒度」を質問項目に入れると、3 サイクル
回らずに 1 サイクルで合意できる。
