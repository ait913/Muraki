---
title: TanStack Query を SwiftUI へ移植する — prefix invalidation キャッシュ + 楽観更新を純粋関数に分離
category: pattern
project: atender
tags: [swiftui, observable, tanstack-query, cache, optimistic-update, invalidation, testing, port]
created: 2026-07-01
sources:
  - Muraki/projects/atender/.designs/20260701-ios-faithful-port-architecture.md (§1.4, A-5)
  - apps/web/src/api/queryKeys.ts / api/hooks/* (atender)
---

## Context

Web (React) が TanStack Query の (a) クエリキャッシュ (b) prefix invalidation マトリクス (c) 楽観更新+ロールバック を持ち、それを SwiftUI ネイティブへ**忠実移植**する場面。SwiftUI に等価物が無く、各 ViewModel が手動 load する素朴実装だと invalidation の連鎖 (出欠変更→today/stats/semesters/day を無効化) が写せず、Web と挙動が乖離する。

## What

TanStack の中核を **`@Observable` 3 部品 + 純粋関数 2 種** に分解する:

1. **`QueryKey`** = `struct { let parts: [String] }`。Web の `queryKeys.ts` (配列キー) を static factory で 1:1 写像。`hasPrefix(_:)` で TanStack の前方一致 invalidation を再現 (`["today","current"]` は `["today"]` に一致)。
2. **`QueryClient`** (`@MainActor @Observable final class`) = 型消去キャッシュ `[QueryKey: CacheEntry(value: Any, isStale, updatedAt)]`。`setData` / `data(for:as:)` / `invalidate(prefix:)` (prefix 一致エントリを stale 化) / `snapshot(matching:)` / `restore(_:)` / `removeAll()` (ログアウト時 `queryClient.clear()` 相当)。
3. **`Query<Value>`** (`@Observable`) = View 観測用ボックス。`state: QueryState<Value>` (`.idle/.loading/.success/.failure`) を公開。
4. **`invalidationTargets(for: Mutation) -> [QueryKey]`** = **純粋関数**。各 mutation の Web `invalidateQueries` 呼び出し集合を写像。副作用ゼロ → 同期 XCTest で全 case 検証。
5. **楽観更新変換** = **純粋関数** (`applyMarkAll(_:status:)` / `applyPatch(_:occurrenceId:status:)` 等)。onMutate で `snapshot` 退避→即時反映、onError で `restore`、onSuccess で `invalidate`。

肝は **invalidation マトリクスと楽観更新変換を「純粋関数」に隔離する**こと。async / View / MainActor から切り離すと Reviewer が同期テストで独立検証でき、実装に寄らない (gotcha `design-doc-must-specify-swift-type-signatures`)。

## Why

- **prefix 一致の再現**: TanStack は配列キーの前方一致で無効化する。`QueryKey.parts: [String]` + `hasPrefix` はこれを最小コストで写せる。enum キーだと prefix 一致が表現しづらい。
- **写像の検証可能性**: `invalidationTargets` を純粋関数にすると、Web hooks の `invalidateQueries({queryKey:[...]})` 群と 1:1 で突き合わせるテストが書け、移植漏れ (例: `deleteAttendance` だけ today も無効化する差異) を回帰で捕まえられる。
- **楽観更新の分離**: `applyPatch` を `(TodayResponse) -> TodayResponse` の純粋変換にすると、「status==nil のみ埋める」「該当 id のみ置換」という Web の onMutate ロジックを実 HTTP 無しでテストできる。ロールバックは snapshot/restore で対称。
- **@Observable の相性**: `QueryClient` を `@Observable` にすると setData/invalidate が View の再描画を自然に駆動する。final のまま依存 (URLSession/QueryClient) を init 注入すればモック可 (gotcha `swiftui-final-mainactor-store-not-mockable-in-xctest`)。

## How to apply

- Web の `queryKeys.ts` を先に読み、`QueryKey` static factory へ全写像。`api/hooks/*` の各 `invalidateQueries` を grep して `invalidationTargets` の表を作る (Web を正、doc に表で固定)。
- invalidation と楽観更新は**必ず純粋関数**に出す。View/Repository に埋めない。
- 自動再フェッチ (staleTime/GC/refetchOnMount) までは最初の骨格で作り込まない。`invalidate` で `isStale` を立て、画面側が `isStale` 判定で `Query.load()` を明示呼びする段階から始め、必要になったら自動化を足す。
- ログアウトで `queryClient.removeAll()` を必ず呼ぶ (Web の `queryClient.clear()`)。
- 関連: [[pattern/home-aggregated-context-switcher]] [[gotcha/design-doc-must-specify-swift-type-signatures]] [[gotcha/swiftui-final-mainactor-store-not-mockable-in-xctest]]
