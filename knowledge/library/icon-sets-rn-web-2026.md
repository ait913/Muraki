---
title: RN + web 二枚看板のフリーアイコンセット選定 (2026-08)
category: library
project: omatase
tags: [icons, lucide, expo, react-native, nextjs]
created: 2026-08-06
sources:
  - https://docs.expo.dev/guides/icons/
  - https://lucide.dev/guide/version-1
  - https://nextjs.org/docs/app/api-reference/config/next-config-js/optimizePackageImports
  - https://pnpm.io/settings/dependency-resolution
---

## Context

omatase (Expo SDK 57 / RN 0.86 + Next.js 16, 部品カタログが RN/web 2 実装) にフリーアイコン 1 系統を導入する選定調査で確定した事実。

## What

- **★ `@expo/vector-icons` は Expo SDK 57 で `expo` の依存から外れている** (expo@57.0.8 の dependencies に無し、node_modules にも無し — 実機確認)。さらに公式 docs が「will be deprecated and is not recommended、`@react-native-vector-icons` へ移行せよ」と明記。フォントベースで web (素の Next.js) 対応も無い。新規採用は不適
- **lucide は 2026-06 に v1.0** で stable 化 (ESM/CJS のみ、ブランドアイコン全削除、aria-hidden デフォルト true、icon rename あり)。`lucide-react` と `lucide-react-native` は同一 monorepo (first-party) で同時リリース・同一バージョン番号。native は react-native-svg ベース (peer `^12〜^15`)、React peer は `^19.0.0` 含む
- lucide の RN 版と web 版は **props 契約が同一** (`size` / `color` / `strokeWidth` / `absoluteStrokeWidth`)。アイコンの named export 名も共通 (native は subset — 採用時は両方に存在するか d.ts で確認)
- `lucide-react` は **Next.js の `optimizePackageImports` デフォルト対象** (barrel import でも使った分だけロード)
- phosphor は web 版 (`@phosphor-icons/react`) が公式だが RN 版 (`phosphor-react-native`) は個人リポジトリ (duongdev)。web 版は 2025-05 から更新停滞
- **pnpm 11 は `minimumReleaseAge` デフォルト 1440 分 (24h)**。v10 以前はデフォルト 0。設定ファイルに値が無くても効いている

## Why

RN/web で「意味論同一・型は platform 別」の部品カタログを保つには、両 platform で名前空間と props が揃う first-party 提供のセットが唯一の低摩擦解。フォントベースは EAS/web で配線が別物になる。

## How to apply

- `lucide-react-native` (mobile) + `lucide-react` (web) を**同一バージョンでピン**する
- 部品カタログ側に `ICONS: Record<IconName, LucideIcon>` のマップを置き、`IconName` union を shared の型で共有 → 片側にアイコンが無いと typecheck で落ちる
- 新アイコン追加時は native 側 d.ts に export があるか確認 (web の方が export 数が多い)
