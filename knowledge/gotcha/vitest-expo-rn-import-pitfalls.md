---
title: Vitest で Expo/React Native モジュールを import する時の落とし穴
category: gotcha
tags: [vitest, expo, react-native, testing, mobile]
created: 2026-05-10
project: global
sources:
  - Tsunagu MVP Reviewer 実走 (worktrees/tsunagu-mobile)
  - mobile/__tests__/unit/notificationStore.test.ts (失敗ログ)
---

## Context

Tsunagu Mobile (Expo + React Native + TypeScript) で Reviewer が Vitest テストを生成した際、Zustand store のテストで実装をimportした瞬間に
`TypeError: Cannot read properties of undefined (reading 'NativeModule')`
が出た。発生箇所は `node_modules/expo-modules-core/build/NativeModule.js:4`。

## What

Zustand store ですら、内部で services 層 (例: `services/notifications/register.ts`) を import していると、推移的に
`expo-notifications` → `expo-modules-core` がロードされ、Vitest (jsdom 環境) は `globalThis.expo.NativeModule` を持たないため落ちる。

設計書からは「store の振る舞いだけ検証」のつもりが、実装の import グラフ次第でテストが起動段階で死ぬ。

## Why

Expo SDK は `expo-modules-core` 経由で Native の `expo` グローバルを参照する。Web/Node ランタイムでは `globalThis.expo` が undefined。Jest なら `jest-expo` preset が一括 mock するが、**Vitest には公式 Expo preset がない**。setup.ts で `vi.mock('expo-notifications', ...)` していても、推移的 import 経路 (例: `services/notifications/handler.ts` が `expo-notifications` を直接 import せず `expo-modules-core` を使うコード経路) を漏らすと刺さる。

## How to apply

Vitest + Expo を組み合わせる場合の Reviewer/Developer 注意:

1. **setup.ts で `expo-modules-core` 自体も mock する** (NativeModule をダミー class で返す):
   ```ts
   vi.mock("expo-modules-core", () => ({
     NativeModule: class {},
     requireNativeModule: () => ({}),
     EventEmitter: class { addListener() {} removeListener() {} },
   }));
   ```
2. **store のテストは store 単体ではなく、import 推移の浅い層から始める** (例: utils/formatTime → 副作用ゼロは安全)。
3. **Zustand store が persist middleware 経由で `@react-native-async-storage/async-storage` を import する場合は必ず setup で mock**。
4. Architect への申し送り: store の責務を「pure な reducer + slice」と「副作用 (API/storage)」で分けると、テストが import 落ちしない。services を直接 import するのではなく、setState で hydrate する DI 方式にする。
5. Vitest を諦めて Jest+jest-expo preset に切り替えるのも有力 (RN コミュニティ標準)。Vitest を選ぶ場合は、上記 mock 群を最初から組む覚悟が必要。

## 関連

- Maestro E2E は **Maestro CLI 未導入だと skip** になるが、yaml は事前に書ける (Reviewer は形式チェックのみ可能)
- Reviewer が「実装コード未読」の制約下で生成すると、`pickModuleExport` のような寛容ヘルパーで関数名のゆらぎを吸収するパターンが有用 (Codex が自発的に採用)
