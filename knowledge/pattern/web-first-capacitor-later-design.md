---
title: Web 先行 → Capacitor 後付けを見越した Next.js 設計 (output: 'export' 縛り)
category: pattern
tags: [nextjs, capacitor, mvp, web-first, output-export, phase-strategy]
created: 2026-05-11
project: global
sources:
  - Muraki/knowledge/library/capacitor-nextjs-ios-2026.md
  - Muraki/projects/tomori/.designs/20260511-phase1-core.md
---

## Context

「最終的に iOS ハイブリッドアプリにしたいが、最初は Web 完結 MVP で検証したい」場面。tomori Phase 1 で採用した戦略。Phase 1 で Server Actions / middleware を 1 箇所でも使うと Phase 1.5 で Capacitor 化したとき作り直しになる。

## What

### 設計時点で受け入れる縛り (Phase 1 から守る)

| 項目 | Phase 1 で禁止 | 代替 |
|---|---|---|
| Server Actions | × | Hono など別バックエンドへ `fetch` |
| Route Handlers POST | × | 同上 |
| `middleware.ts` (近未来 `proxy.ts`) | × | クライアント `<SessionGuard>` で CSR 判定 |
| ISR / on-demand revalidate | × | 静的 + クライアント `fetch` |
| `next/image` (loader 最適化) | × | 素の `<img>` + CSS サイズ |
| `next/headers` (`cookies()` 等) | × | document.cookie / fetch クッキー |
| 動的ルート `[id]` | △ | クエリパラメータ (`?id=`) に倒す |
| `trailingSlash: false` | × | `true` 必須 (WebView 解釈) |

### リポジトリ分割の定石

```
apps/web   ← Next.js 16 static export (Capacitor で同梱予定)
apps/api   ← Hono on Node (Coolify 上で独立コンテナ)
packages/* ← shared 型・暗号・LLM ラッパ等
```

Phase 1 では Nginx で `/api/*` → Hono、それ以外 → web 静的配信。Phase 1.5 では web の export を `dist/` から `npx cap copy` で iOS バンドルに同梱、Hono は同じサーバを叩き続ける。

### 同一オリジン仕様の維持

- Phase 1 では `tomori.<host>` 同一オリジンで `/api/*` を叩く → CSRF 対策が double-submit で済む
- Phase 1.5 で iOS WebView は `capacitor://localhost` 起源、API は `https://tomori.<host>` → cross-origin になる → **CORS allowlist + 認証は Bearer cookie 持参** で対応 (Phase 1.5 設計時にスキーム変更を明示)

### auth の流儀

- middleware 使えないので「`<SessionGuard>` で `useEffect` 中に `/api/me` 叩いて未認証なら `/login` に redirect」が定石
- SSR 時の認証分岐がない代わりに、初回 paint で 1 フレームだけ空画面が出る → スケルトン UI で吸収

### Capacitor 後付け時に追加コストになるもの

- Time-Sensitive entitlement 申請 (Phase 1.5)
- APNs `.p8` + Key ID + Team ID の管理
- iOS 26 SDK ビルド (Xcode 26+)
- HealthKit 権限 prompt + `Info.plist` の Usage Description

## Why

- Capacitor は「最終 build 時に static export を同梱する」モデル。Next.js の SSR/middleware/Server Actions が混ざっていると Capacitor build 時に runtime が無くて死ぬ
- Phase 1.5 で発覚すると、UI 改修 + 認証経路再設計 + API 分離が同時に来て地獄になる
- 最初から `output: 'export'` 縛りで書くと、Web 単独配信もできるし iOS ラップも単なる `npx cap add ios` で済む

## How to apply

1. Phase 1 設計 doc に **「output: 'export' 縛り」を §1 レベルで明文化**
2. 設計 doc の §不採用案に「Server Actions で済ます案を却下」を **検討した跡として残す** (再検討ループ防止)
3. `apps/web` `apps/api` `packages/*` の workspace を最初から分ける (途中分割は import パス変更が辛い)
4. 認証は cookie + 同一オリジン (Phase 1) → Phase 1.5 で Capacitor 化する際 CORS + cookie withCredentials に切替予定であることを設計に書く
5. Developer (Codex) に渡す指示文で「next/image / Server Actions / middleware を **1 行でも書いたら NG**」を強調
6. Reviewer は `apps/web` 内に `next/headers` / `cookies()` / `'use server'` / `middleware.ts` / `next/image` の grep を 1 つテストとして組み込むと安全
