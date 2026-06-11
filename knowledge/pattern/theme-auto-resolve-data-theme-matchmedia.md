---
title: テーマ auto を JS で解決し data-theme 常設 + matchMedia ライブ監視
category: pattern
project: global
tags: [theme, dark-mode, prefers-color-scheme, matchMedia, css-variables, react]
created: 2026-06-02
sources:
  - Muraki/projects/atender/.designs/20260602-ui-improvements.md (項目5)
  - apps/web/src/lib/useTheme.ts (atender)
---

## Context

ダーク/ライト + 「自動 (OS 追従)」の 3 モードを持つ Web アプリ。「自動」が OS 設定に追従しない/切り替わらないバグの定番。

## What

auto 時に `data-theme` 属性を**削除して CSS の `@media (prefers-color-scheme)` 任せ**にする実装は脆い。代わりに:

1. **auto を JS 側で実 light/dark に解決**し、`data-theme` を**常に明示セット**する (削除しない):
   ```ts
   function resolveTheme(theme: "auto"|"light"|"dark"): "light"|"dark" {
     if (theme !== "auto") return theme;
     if (typeof window === "undefined" || !window.matchMedia) return "dark"; // SSR/未対応の既定
     return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
   }
   // 常に setAttribute("data-theme", resolved) する。removeAttribute はしない。
   ```
2. **初期化 (render 前) も同じ解決ロジック**で data-theme を確定 (FOUC 回避)。
3. **auto のときだけ matchMedia の `change` を監視**して再解決 → ライブ追従。effect cleanup で `removeEventListener`:
   ```ts
   useEffect(() => {
     applyResolved(resolveTheme(theme));
     if (theme !== "auto" || !window.matchMedia) return;
     const mql = window.matchMedia("(prefers-color-scheme: dark)");
     const onChange = () => applyResolved(resolveTheme("auto"));
     mql.addEventListener("change", onChange);
     return () => mql.removeEventListener("change", onChange);
   }, [theme]);
   ```
4. CSS 側は **`[data-theme]` 単系に統一**。`@media (prefers-color-scheme)` の定義は撤去 (data-theme が常に立つので二重発火・齟齬源になる)。`:root` をデフォルト (dark)、`:root[data-theme="light"]` / `:root[data-theme="dark"]` で上書き。

## Why

- `@media` 任せ + 属性削除だと、(a) OS 変更時に React state と DOM がズレる、(b) `:root:not([data-theme])` と `@media` の組合せが他の `[data-theme]` 明示ルールと specificity/順序で齟齬を起こす。
- data-theme を常設すると CSS 経路が 1 本化し、「今どっちか」が DOM 属性で一意に決まる。matchMedia listener で OS のライブ切替も拾える。
- localStorage は従来通り auto 時は削除 (= 次回 "auto" 復元)。UI のセグメント選択状態は React state が auto/light/dark を保持するので 3 択表示は正しく出る (data-theme は light/dark しか入らないが別物)。

## How to apply

- 新規で 3 モードテーマを作るなら最初からこの形。`@media (prefers-color-scheme)` を**トークン適用の主経路にしない** (no-JS フォールバックとして残すかは要件次第だが、JS 常設と併用すると二重定義になるので原則撤去)。
- テスト: `window.matchMedia` を matches 可変 + change 発火できる stub に差し替え、`resolveTheme` の純粋検証 + `setTheme("auto")` 後の change 発火で data-theme がライブ更新されること + cleanup で removeEventListener されることを assert。
- 関連: [[gotcha/design-must-specify-component-prop-contract-for-render-tests]]
