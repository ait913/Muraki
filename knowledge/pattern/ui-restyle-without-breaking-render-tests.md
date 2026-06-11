---
title: 既存 UI を視覚再設計する際に描画テストを壊さない設計規律
category: pattern
tags: [ui, redesign, restyle, design-token, data-testid, render-test, responsive, css-first]
created: 2026-06-08
project: kinketsu-taisaku
sources:
  - Muraki/projects/kinketsu-taisaku/.designs/20260608-ui-cloudflare-redesign.md
  - Muraki/knowledge/pattern/cloudflare-dashboard-design-language.md
---

## Context

既に動いている React アプリの **見た目だけ** を別デザイン言語 (例: Cloudflare dashboard 風) に全面再設計する場面。データモデル/API/挙動は変えない「純 UI 再設計」。Reviewer が既存の描画テスト (data-testid 依存) を多数持っている状態で、テストを壊さず restyle する設計の組み方。

## What

純 UI 再設計を「別機能」として 1 本の設計 doc に切り、以下を**明示**すると developer/reviewer が安全に回せる:

1. **変更スコープの境界を表で固定**: 触ってよいファイル (`client/` の styles.css / components / routes) と **絶対に触らないもの** (`src/` backend, `api/*.ts` の DTO 型・fetch ラッパ, query key, invalidate) を列挙。「backend を 1 行も変えない」と書く → developer が API を勝手にいじる事故を防ぐ。
2. **data-testid を 3 分類**して管理:
   - **温存 (変更/削除禁止)**: 既存テストが依存する testid を一覧化し、各々の「不変条件」(例: `record-unpaid-mark` は paid=false のときのみ存在 / `summary-current` は currentBalance===null で非存在 / LineChart series id 文字列 `confirmed`/`forecast` 不変) まで書く。
   - **新規追加**: 新構造 (サイドバー/テーマトグル/空状態/テーブル行) に付ける testid。
   - **変更/削除**: 原則 **ゼロ**。「削除/改名しない」と宣言すると Reviewer は既存 N 件をそのまま流せる。
3. **prop 契約は不変**と明記: restyle は内部 className/CSS のみ。コンポーネント props の型を追加/削除/変更しない。
4. **デザイントークンは CSS-first (`@theme` + `[data-theme]`) に集約**: 色は全て `var(--color-*)` 経由、hex ハードコードを新規に書かない。旧テーマ色 (例ティール) は **追記でなく全置換** (grep して残らないようにする)。
5. **レスポンシブは「両構造を常に render + CSS で表示切替」**: モバイル bottom tab とデスクトップ sidebar を両方 DOM に出し `@media` で `display` 切替。→ jsdom はメディアクエリを評価しないので **両構造が DOM に存在することだけ単体テストで検証**でき、視覚切替自体は手動/MCP スクショに委ねる。
6. **構造を持ち上げない最小変更**: トップバー等の共有領域も、ページ依存要素 (月送り・主アクション) は各ビューが自前 toolbar として持つ。AppShell↔ビューに新規 context/portal/prop 配線を増やさない。

## Why

- 描画テストは data-testid とテキスト規約と「条件付き存在」に依存する。restyle で DOM 構造を変える誘惑が強いが、**testid とその不変条件を温存すれば既存テストは無改修で通る** → Reviewer の再実行コストがゼロになり、再設計の「機能不変」が機械的に保証される。
- スコープ境界を表で固定すると、codex (developer) が「ついで最適化」で backend や API 型を触る逸脱を抑止できる。
- CSS-first トークン集約 + 旧色全置換にしないと、ティール hex が残って「どっちつかず」の混在になる (仕様 md の追記でなく置換 規律と同じ)。

## How to apply

- 純 UI 再設計は既存設計 doc を置換せず **新規 doc** にし、「本 doc が旧 doc の §UI を上書きする。ただし §prop契約/data-testid は温存」と冒頭で関係を宣言。
- 設計 doc に「温存 data-testid 表 (testid + 不変条件)」「新規 testid 表」「変更/削除 = なし」の 3 セクションを必ず置く。Reviewer はここを根拠に既存非破壊 + 新規追加分のテストだけ書く。
- テーマ 3 モードは [[pattern/theme-auto-resolve-data-theme-matchmedia]] (data-theme 常設 + matchMedia 監視) に乗せ、CSS に `@media (prefers-color-scheme)` を主経路で書かない。
- 視覚言語のトークン本体は別 knowledge を参照 (本件は [[pattern/cloudflare-dashboard-design-language]])。本パターンは「それを既存アプリに安全移植する手続き」側。
