---
title: Expo の `process.env.EXPO_PUBLIC_*` は **直接参照** しないと bundle に inline されない
category: gotcha
project: global
tags: [expo, react-native, env, web, static-replacement, build]
created: 2026-05-10
sources:
  - https://docs.expo.dev/guides/environment-variables/
  - https://github.com/expo/expo/blob/main/packages/babel-preset-expo/transform-plugins.ts
---

## Context

Expo (SDK 50+) は `process.env.EXPO_PUBLIC_*` を build時に **literal 値で static 置換** する。これにより mobile bundle / web bundle に env 値が inline される。

しかし「動的アクセス」(下記) では置換が効かず、 **runtime に `process.env` を参照** することになる。React Native / browser には `process.env` が存在しないため `undefined` を返し、API_BASE が空になり fetch が相対URLで飛んで 404 になる。

## What

### ❌ static 置換が効かないパターン (bundle に env 値が embed されない)

```ts
// 動的アクセス
const url = (globalThis as any).process?.env?.EXPO_PUBLIC_API_BASE;

// 関数経由の動的アクセス
function getEnv(name: string) {
  return process.env[name];
}
const url = getEnv("EXPO_PUBLIC_API_BASE");

// bracket 記法
const url = process.env["EXPO_PUBLIC_API_BASE"];
```

### ⭕ 効くパターン (build時に literal 化)

```ts
// 必ず "process.env.EXPO_PUBLIC_*" のドット記法直接参照
const url = process.env.EXPO_PUBLIC_API_BASE ?? "";
```

build 後の bundle:

```js
// ❌ 動的: bundleにそのまま残る → web で undefined
const url = process.env.EXPO_PUBLIC_API_BASE;

// ⭕ 直接: 置換済み
const url = "https://tsunagu.appily.run";
```

## Why

`babel-preset-expo` の transform-plugin が **AST level で `MemberExpression(process.env.<UpperCase_underscore>)` パターンだけマッチ** する。
- `process.env[var]` は `ComputedMemberExpression` で対象外
- `globalThis.process.env.X` も chain が違うので対象外
- `getEnv("X")` 関数間接化は完全にopaque

これは Next.js / Webpack の `process.env.NEXT_PUBLIC_*` の DefinePlugin と同じ仕組み。**コンパイラが文字列マッチで literal 化** している。

## How to apply

1. **新規mobile実装で env を読む箇所**は必ず `process.env.EXPO_PUBLIC_X` の形でドット記法直接アクセスする
2. **既存コードで動的アクセスを使ってる箇所**を `grep -rn "scope\.process\|process\.env\[\|getEnv(" src/` で洗い出して直接参照に直す
3. **Web export で fetch が 404 になる**等の症状が出たら、まず bundle に env 値が embed されているか確認:
   ```sh
   curl https://your-app.com/_expo/static/js/web/index-XXX.js | grep "your-api-domain.com"
   ```
   0件なら static 置換が効いていない (動的アクセスが原因)。
4. **persisted store の初期値**も同じ罠。`zustand persist` で `demoMode: false` を hardcode すると env (`EXPO_PUBLIC_DEMO_MODE`) が反映されず本番 (`tel:119`) を踏むリスク。初期値も `process.env.EXPO_PUBLIC_DEMO_MODE === "true"` で生成する。

## 関連

- `mobile/.gitignore` で `.env*` 全除外すると、CI (Coolify/Vercel等) で `.env` が git clone後に存在せず env 値全部欠落する。`.env*.local` だけ ignore に絞り、`.env` は commit する慣習が安全 (EXPO_PUBLIC は全部公開情報のため secret 漏洩リスクなし)。
