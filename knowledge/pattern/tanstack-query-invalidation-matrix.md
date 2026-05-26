---
title: TanStack Query の invalidation を設計 doc にマトリクスで書く
category: pattern
project: global
tags: [tanstack-query, react-query, cache-invalidation, design-doc, mutation, frontend]
created: 2026-05-15
sources:
  - https://tanstack.com/query/v5/docs/framework/react/guides/invalidations-from-mutations
  - Muraki/projects/atender/.designs/20260515-redesign.md §7
---

## Context

TanStack Query (旧 React Query) で SPA を組むとき、「mutation 後にキャッシュが古いままで、ブラウザリロードしないと反映されない」 (= invalidate 漏れ) は最頻ハマり所。

事故パターン:
- Mutation hook 作成者は「自分の関心ドメイン (e.g. `["meetings"]`) だけ invalidate」する
- 同じデータを別の queryKey (`["today"]`, `["stats"]`) でキャッシュしてる画面が古いまま
- 検証時にリロードして問題に気付かない (TanStack Query は default で `refetchOnWindowFocus` だが、開発機の挙動と本番ユーザーの挙動が違う)
- 結果「リロードしないと反映されない」苦情、原因特定で 30 分溶ける

Atender redesign で Researcher が「★3 含意」として明示。本パターンはその設計対応。

## What

### 設計 doc に「Mutation → Invalidate マトリクス」を表として書く

設計 doc の API セクションとは別に、フロント側で **mutation 種別 × 影響を受ける queryKey** を 1 つの表で書く。Developer はそれを引き写しで実装する。

| Mutation                                | 必須 invalidate queryKey                                                  |
| --------------------------------------- | ------------------------------------------------------------------------- |
| `POST /api/auth/sign-out`               | `["session"]`, `["me"]`, `queryClient.clear()`                            |
| `PATCH /api/me`                         | `["me"]`, `["session"]`, `["templates"]` (schoolId 変更時)                |
| `POST /api/meetings`                    | `["user-timetable", utId]`, `["today", *]`, `["stats", semesterId]`       |
| `POST /api/attendance/mark-all-present` | `["today", *]`, `["stats", semesterId]`                                   |
| ...                                     | ...                                                                       |

### 補助: queryKey naming convention をひとつのファイルに集約

```ts
// src/api/queryKeys.ts
export const QK = {
  me:             () => ["me"] as const,
  today:          (date?: string) => ["today", date ?? "current"] as const,
  userTimetable:  (id: string) => ["user-timetables", id] as const,
  stats:          (semesterId: string) => ["stats", semesterId] as const,
  // ...
} as const;
```

- 文字列リテラルを散らさない、変更時は 1 箇所
- TypeScript 型推論で typo 抑制
- 大規模化したら `as const` 必須 (`useQuery` 側の型推論強化)

### 補助: mutation は inline ではなく named hook (テスト容易性)

各 mutation は **専用の named hook** として export する。コンポーネント内に `useMutation({...})` を inline で直書きしない。

```ts
// src/api/hooks/useApi.ts (推奨)
export function useUpdateSchedule(scheduleId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (vars: UpdateScheduleVars) => api.patchSchedule(scheduleId, vars),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: QK.schedule(scheduleId) });
      qc.invalidateQueries({ queryKey: QK.schedules(eventId) });
      qc.invalidateQueries({ queryKey: QK.progress(eventId) });
    },
  });
}
```

命名は `use<Action><Resource>` 形式 (`useCreateEvent` / `useUpdateSchedule` / `useDeleteFeature` / `useCompleteSchedule` 等)。理由:

- Reviewer は `vi.spyOn(api, "useUpdateSchedule")` で specific hook を spy できる。inline `useMutation` だと「どの呼び出しが invalidate 検証対象か」が文脈不明で spy 不能
- 設計 doc の matrix と実装が `import { useUpdateSchedule } from "@/api/hooks/useApi"` で 1:1 対応する → reviewer が候補名を heuristic に探さなくて済む
- 同じ mutation を複数コンポーネントから呼ぶ時の重複ロジックを防ぐ

設計 doc の matrix には **mutation/hook 名/invalidate queryKey の 3 列** を入れると、命名規約と invalidate 規約を 1 表で固定できる (例: omatase-demo §7.11)。

### 補助: 共通 mutation hook で invalidate を強制

```ts
export function useApiMutation<TVars, TData>(
  mutationFn: (vars: TVars) => Promise<TData>,
  invalidate: Array<readonly unknown[] | { predicate: (q: Query) => boolean }>
) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn,
    onSuccess: () => {
      for (const target of invalidate) {
        if (Array.isArray(target)) qc.invalidateQueries({ queryKey: target });
        else qc.invalidateQueries({ predicate: target.predicate });
      }
    },
  });
}
```

各 mutation hook が `invalidate` 配列を**必ず引数で渡す**設計にすると、漏れに気付きやすい。「設計 doc の表」と「実装の hook 引数」が 1:1 で照合できる。

### ワイルドカード invalidate

`["today", *]` のように引数違いを全部潰したい場合は `predicate` 形式:

```ts
qc.invalidateQueries({ predicate: q => q.queryKey[0] === "today" });
```

設計 doc では `["today", *]` 表記で書き、実装で predicate に展開する規約にする。

## Why

- **invalidate 漏れ = 「リロードしないと反映されない」苦情の最大原因**。設計時に潰せば実装で考えなくて済む
- **設計 doc の表は Reviewer のテスト根拠になる**。Reviewer は「mutation 後に queryKey が refetch される」を assert するテストを表から自動生成できる
- **Developer の判断削減**。「この mutation で `["stats"]` も invalidate すべき?」を実装中に考えさせない、設計で決め切る
- **TanStack Query の `setQueryData` で楽観更新する場合も、最終的に `invalidate` で server-true な値で上書きする** のがベスト (Optimistic と invalidate は競合しない、後者が常に勝つ)

## How to apply

1. **設計 doc に「Mutation → Invalidate マトリクス」セクションを必須項目化**。Architect が API セクションの隣に書く
2. **queryKey 命名規約**は `src/api/queryKeys.ts` に集約、文字列リテラル散布禁止
3. **`useApiMutation` 共通 hook** を作り、各 mutation hook はそれを呼ぶだけにする
4. **Reviewer は「全 mutation について該当 queryKey が invalidate されるテスト」を 1 個ずつ書く**。`vi.fn()` で `invalidateQueries` を mock してマトリクス通り呼ばれるか assert
5. **`refetchOnWindowFocus` には頼らない**。開発機 (active tab) と本番ユーザー (background tab) で挙動が違う罠を避け、明示 invalidate で全部担保

## 反例・限界

- マトリクスが 30+ 行に膨らむと管理しんどい。**1 mutation = 1 row** を維持し、横軸の queryKey は短い名前で書く
- predicate 形式は便利だが、過剰使用すると「どの query が invalidate されるか」が静的解析できなくなる。原則は配列形式、本当に必要な所だけ predicate
- 楽観更新を併用する場合、`onMutate` で `setQueryData`、`onError` で rollback、`onSettled` で `invalidate` のフルパターンを書く。invalidate だけだと UI が一瞬古い値を表示する事故あり

## 関連

- [[pattern/timetable-app-ux-patterns]] — UX 側のキャッシュ罠 (リロード問題) の文脈
- [[pattern/touri-design-philosophy]] — 「1 箇所変更で派生」の方向と一致 (queryKey 集約)
