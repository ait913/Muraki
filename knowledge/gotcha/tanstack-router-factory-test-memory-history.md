---
title: TanStack Router factory export 時のテスト用 memory history 注入
category: gotcha
tags: [tanstack-router, vitest, jsdom, testing]
created: 2026-05-13
project: atender
sources:
  - https://tanstack.com/router/latest/docs/framework/react/api/router/createMemoryHistoryFunction
---

## Context

Atender web (Vite + React + TanStack Router) で Reviewer が RTL + jsdom 環境のテストを書く際、router を Provider 経由で立ち上げる helper を作ろうとした。

実装側は `createAppRouter(queryClient)` を factory export しており、`router` 単体 instance は export していない (queryClient を渡すため)。

テスト helper は `import { router } from "@/router"` を期待して書かれていたが当然 undefined。`router.navigate is not a function` で全 37 件 fail。

## What

TanStack Router で次の構造のとき:

```ts
// src/router.tsx
export function createAppRouter(queryClient: QueryClient) {
  return createRouter({ routeTree, context: { queryClient } });
}
```

テスト helper は **factory を呼び**、しかも jsdom では browser history が空なので **memory history を注入** しないと initial path が反映されない:

```ts
import { createMemoryHistory, RouterProvider } from "@tanstack/react-router";
import { createAppRouter } from "@/router";

const router = createAppRouter(queryClient);
(router as any).history = createMemoryHistory({ initialEntries: [initialPath] });
await router.navigate({ to: initialPath }).catch(() => { /* guard redirect は無視 */ });

render(<QueryClientProvider client={queryClient}><RouterProvider router={router} /></QueryClientProvider>);
```

`navigate` を `try/catch` で囲うのは、guard で `throw redirect()` が走るルート (`/`, `/settings` 等の `@auth` 系) に initialPath を指定した場合に navigate Promise が reject するため。

## Why

- factory export パターンは「context (= queryClient) を runtime に渡したい」要件で正当。`router` を top-level export すると queryClient と循環する
- TanStack Router の `createRouter` はデフォで `createBrowserHistory()` を使うので、jsdom 環境 (location が `about:blank` のまま) では initialPath が `/` 扱いになる
- `createMemoryHistory({ initialEntries: [path] })` を `(router as any).history =` で差し替えるのが現状の公開 API 範囲では最短 (`createRouter` の `history` option は v1 では受け取らない)
- guard が `beforeLoad` で `throw redirect()` する設計 (auth 強制) では navigate がエラーになるが、その redirect 自体が router state に反映されればテストの目的 (path 検証) は果たせる

## How to apply

1. Architect は設計 doc の「テスト基盤」セクションで router の **export 形 (factory or instance)** を明記する
2. Reviewer は `src/router.tsx` の **export シグネチャだけ** を grep で確認 (内部実装は読まない範囲)
3. Reviewer の `tests/utils/render.tsx` には `createMemoryHistory` 注入 + `navigate().catch()` を最初から仕込む
4. guard リダイレクトのテスト assert は `await waitFor(() => expect(router.state.location.pathname).toBe("/login"))` で十分。`navigate` の Promise resolve は待たない
