---
title: vi.mock("node:fs/promises") は specifier が違うと当たらない
category: gotcha
tags: [vitest, mock, esm, nextjs, reviewer]
created: 2026-05-10
project: global
sources: ["meishilink-mvp Phase 4 reviewer 失敗 5 件"]
---

## Context

Reviewer が Next.js App Router の route handler (例: `src/app/u/[handle]/logo/route.ts`) のテストを書く際、ファイル読み込みを mock するために `vi.mock("node:fs/promises", ...)` を使ったが、テスト 5 件が「200 期待 / 404 受信」で失敗した。

実装は `import { readFile } from "fs/promises"` (specifier "fs/promises")。テストは `vi.mock("node:fs/promises", ...)` (specifier "node:fs/promises")。

## What

Vitest (Vite ESM resolution) は `vi.mock(specifier, factory)` の **specifier 文字列で完全一致**の resolver を持つ。`"node:fs/promises"` と `"fs/promises"` は別 specifier として扱われ、片方だけ mock しても他方の import は実物の `fs/promises` が呼ばれる。

実物が呼ばれるとテストが用意した dummy ファイルが存在せず ENOENT → route が 404 を返す。設計違反 (RED) ではなく **テスト側不備 (mock specifier 不一致)** だが、判定ミスると Developer に無駄な修正依頼が飛ぶ。

## Why

- Node.js は `fs/promises` と `node:fs/promises` を **同一モジュールにエイリアス解決**するため、実装側ではどちらの import も動く (差は出ない)
- Vitest の mock は ES module の specifier graph 単位で hook するため、エイリアス解決前の文字列で一致を判定する
- 実装と書き方が違う specifier で mock すると、エイリアスを通って実物が解決される

## How to apply

Reviewer がファイルシステム mock を書くときは **両方の specifier を mock する**:

```ts
const readFileMock = vi.hoisted(() => vi.fn());
vi.mock("fs/promises", () => ({ readFile: readFileMock }));
vi.mock("node:fs/promises", () => ({ readFile: readFileMock }));
```

同様の双子 specifier (実装が片方、テストが片方になりがち):
- `crypto` / `node:crypto`
- `path` / `node:path`
- `fs` / `node:fs`
- `os` / `node:os`
- `stream` / `node:stream`

ESLint の `import/no-nodejs-modules` を導入しているなら specifier がプロジェクト内で揃うので問題は起きにくいが、Next.js プロジェクトはルール緩めのことが多いので Reviewer 側で防御する。

**判定の原則**: route テストが「全件 404」のように同一ステータスで落ちたら、認可ロジックや schema 違反の前に **mock specifier 不一致** を疑え。実装の import 文を **diff で 1 行だけ**確認する (CLAUDE.md の RED 例外条項で許容)。
