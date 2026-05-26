---
title: 設計 doc にテスト用 app export path を明示しないと Developer と Reviewer が分離して詰む
category: gotcha
tags: [hono, design-doc, test-infra, reviewer-orchestration]
created: 2026-05-13
project: global
sources:
  - Muraki/projects/atender/.designs/20260513-mvp.md §2,§4,§9
  - Muraki/worktrees/atender-mvp 第1回 Reviewer 召集 (76/81 fail, single cause)
---

## Context

Atender MVP の Reviewer 召集で、`apps/api` のテストを設計 doc 根拠で生成 → Vitest を実行 → 81 件中 76 件 fail。失敗の原因はすべて単一: テスト helper が import すべき Hono `app` の export path が**設計 doc に明示されていなかった**ため、helper が TODO stub で残り、ほぼ全ての `app.request()` 呼び出しが落ちた。

Developer は `src/routes/*.ts` `src/middleware/*.ts` `src/auth.ts` `src/db.ts` まで書いていたが、それらを束ねる **`src/app.ts` or `src/index.ts` の Hono インスタンス組み立て箇所を書き忘れていた**。設計 doc が `tsx watch src/index.ts` を package.json に書きつつ、§4 で「Hono Router」とだけ書き、export 名・path を明示しなかったため、Reviewer は推測、Developer は実装漏れに気づかなかった。

## What

「設計 doc が `framework + endpoint table` までしか書かず、`実装エントリの export 名・path` を書かないと、Reviewer (テスト) と Developer (実装) の間で**接続点が一致しない**」というパターン。

具体的に最低限明示すべき項目:

- テストから import すべき **app インスタンスの module path と export 名** (例: `apps/api/src/app.ts` から `export const app = new Hono()`)
- そのファイルが **server listen を行わない** こと (テストでは `serve()` を呼ばない、`app.request()` で叩く)
- Prisma client などの依存も同様に **named export** で取れること

これが書かれていれば Reviewer の `helpers/app.ts` は `export { app } from "../../src/app"` で 1 行確定する。

## Why

Hono / Express / Fastify などの Web FW は「アプリ組み立て」と「サーバ起動」をどう分けるか自由度が高く、慣習が複数存在する:

- パターン A: `src/index.ts` が `app` も serve も持つ → テストで `app` だけ named export して serve はファイル末尾の `if (import.meta.url === ...)` で守る
- パターン B: `src/app.ts` (app のみ) + `src/server.ts` (serve のみ)
- パターン C: factory pattern (`createApp(deps)` を返す) → テストでは依存を mock 注入できる

設計 doc がこのいずれかを宣言しないと、Developer と Reviewer が別の前提で動く。さらに **Leader はコードを見ない** ので、両者の前提ズレに気付くのが Reviewer 召集 (テスト実行) の瞬間まで遅れる。

## How to apply

### Architect の責任 (新規 API 設計時の必須項目)

「テスト基盤」セクション (設計 doc §9 等) に以下を明示:

```md
### Backend エントリポイント

- `src/app.ts`: `export const app = new Hono()` で組み立て、route / middleware を mount。**serve は呼ばない**
- `src/index.ts`: `src/app.ts` から `app` を import して `serve({ fetch: app.fetch, port })` のみ呼ぶ。テストからは import しない
- テストは `import { app } from "../../src/app"` で `app.request(path, init)` を叩く
- 依存注入: factory にしない (シンプル優先)、テスト DB は `process.env.DATABASE_URL` 切替で対応
```

3 行 + 1 コードブロックで Reviewer / Developer 両方の前提が確定する。

### Reviewer の振る舞い

設計 doc に上記が無い場合:

1. **テスト生成前に Leader に上申** ("app export path 未明示。仮で `src/app.ts` 想定で進めてよいか")
2. 仮の想定で進めるなら helper を 1 箇所 (`tests/helpers/app.ts`) に集約。各 test file から直接 `src` を import しない → 後から差し替え可能にする
3. 第 1 回実行が「app entry 不在」で大量 fail したら、**判定は RED**、テスト本体の品質は別途見ない (entry が無いと評価不能)

### Developer の振る舞い

設計 doc に明示があれば従う。明示がなくとも以下を default にすると Reviewer と噛み合う:

- `src/app.ts` で `export const app` (named)
- `src/index.ts` は薄い serve wrapper

これは Hono の dev guide でも推奨されている分離パターン。
