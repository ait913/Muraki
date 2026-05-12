---
title: pickFirstFunction の Object.values fallback で Prisma.sql タグ等を誤拾い
category: gotcha
tags: [vitest, test-helper, prisma, dynamic-import]
created: 2026-05-10
project: tsunagu
sources:
  - Muraki/projects/tsunagu/.designs/20260510-mvp-foundation.md
  - Muraki/worktrees/tsunagu-backend/backend/__tests__/helpers/runtime.ts
---

## Context

Reviewer がテスト生成時、対象モジュールの export 名が設計書に明示されていない場合、
`pickFirstFunction(mod, ["nameA","nameB"])` で複数候補を試し、見つからなければ
`Object.values(mod).find(typeof v === "function")` にフォールバックするヘルパーを使った。

## What

- フォールバックが **意図しない関数** を拾うことがある
  - Prisma の `Prisma.sql` テンプレートタグ (`{values:[...], strings:[...]}` を返す)
  - 別 export の `signRefreshToken` を `signAccessToken` の代わりに拾う、など
- すると `tryInvoke` の attempts が **二重署名** や **SQL タグの結果オブジェクト** を返してしまい、
  「型エラー」「JWT の sub に別 JWT が入る」など解析が困難な失敗になる

## Why

- ES Module の export 順は宣言順 (おおむね) だが保証はない
- テストは「実装の export 名に依存しない柔軟性」を狙ったが、
  動的 import 経由では Prisma.sql のような静的タグも export 扱いで紛れ込む
- attempts が「複数の引数形を試す」と、内部で型変換が暗黙に成功して**意味のない値**を返すケースが拾えない

## How to apply

1. **設計書に export 名を必ず明記**してもらう (Architect への要請)
   - 例: `signAccessToken(sub: string): Promise<string>` までシグネチャ確定
2. テスト側は `pickFirstFunction` のフォールバックを使わず、**正規候補名を直接プロパティアクセス**
   - `mod.signAccessToken ?? mod.createAccessToken` のような明示的フォールバック
3. tryInvoke の attempts を増やすより、**1 つに絞り、シグネチャを設計書から確定させる**
4. 取得した値は型ガード (`typeof v === "number"`、特定 key の有無) で防御し、
   失敗時に **値を JSON.stringify でエラーメッセージに出す** と原因特定が早い
