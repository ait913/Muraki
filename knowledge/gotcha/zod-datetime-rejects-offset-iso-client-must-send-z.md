---
title: zod .datetime() は +09:00 形式の ISO8601 を拒否する — クライアントは必ず toISOString() で送る
category: gotcha
tags: [zod, iso8601, timezone, jst, api-contract, vitest]
created: 2026-07-29
project: atender
sources:
  - "atender .designs/20260729-personal-calendar-rebuild.md §5.1 / §9 W4"
  - "apps/web/src/lib/personalEventDays.ts (jstDayStartIso / jstNextDayStartIso / fromDateTimeLocal)"
---

## Context

atender の個人カレンダー再構築で「JST 日付 (YYYY-MM-DD) → instant」の変換を
クライアント側ヘルパに切り出した。設計は `start`/`end` を `z.string().datetime()` と規定していた。

## What

**zod 3 の `z.string().datetime()` は既定で `offset: false`** = 末尾 `Z` の UTC 表記しか通さない。
`"2026-07-23T00:00:00.000+09:00"` は**同じ instant を指すのに 400 VALIDATION_ERROR で落ちる**。

```
z.string().datetime().safeParse("2026-07-23T00:00:00.000+09:00").success  // false
z.string().datetime().safeParse("2026-07-22T15:00:00.000Z").success       // true
```

atender では JST 変換ヘルパが offset 形式の文字列を組み立てていたため、
**Web からの個人予定の作成・更新が全経路 400**（終日/時刻あり/一括作成/編集の 4 経路）になっていた。
instant としては正しいので、ログを見ても「日付が違う」ようには見えない。

## Why

- `new Date(...)` を経由せず `${date}T00:00:00.000+09:00` のように文字列連結で組むと offset 形式になる。
- 型は `string` なので TypeScript は何も言わない。サーバ zod だけが弾く。
- ユニットテストが「同じ instant か」を `new Date(a).getTime() === new Date(b).getTime()` で比較していると
  **両形式が等価**になり、この欠陥をすり抜ける。

## How to apply

- **クライアント側で instant を作るときは必ず `new Date(...).toISOString()` を最終形にする。**
  文字列連結で offset を書かない。
- **wire 契約のテストは「同じ instant か」でなく「serialization の形」まで assert する**:
  `expect(String(body.start)).toMatch(/Z$/)` を 1 行足すだけで検出できる。
- 逆に、offset 形式も受けたい設計なら zod 側を `z.string().datetime({ offset: true })` と
  **設計docに明示**する (既定を暗黙に頼らない)。
- 検出コストが最も低いのは `msw` で実 HTTP body を捕捉する component テスト。
  hook をモックすると「クライアントが組んだ body」までしか見えないが、それでも形は見える。
