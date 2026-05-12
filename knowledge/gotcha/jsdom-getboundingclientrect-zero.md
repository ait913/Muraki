---
title: jsdom の getBoundingClientRect は常に 0 を返す
category: gotcha
tags: [vitest, jsdom, testing-library, layout, css]
created: 2026-05-10
project: global
sources:
  - "Muraki/projects/omatase-design-mock/.designs/20260510-design-mock.md (§10.9 MobileFrame 幅検証)"
---

## Context

OMATASE デザインモック (Vitest + RTL + jsdom) のレビューで、設計 §10.9 にあった
「MobileFrame の幅が PC で 375px、モバイルで viewport 幅まで広がる」
という挙動仕様をテスト化したところ、`getBoundingClientRect().width` が常に `0` になり 2 件失敗した。

## What

jsdom は **DOM API は提供するが CSS レイアウトを実計算しない**。
そのため以下の API はすべて 0 / 空 / フォールバック値を返す:

- `element.getBoundingClientRect()` → `{ x: 0, y: 0, width: 0, height: 0, ... }`
- `element.offsetWidth` / `offsetHeight` → `0`
- `element.clientWidth` / `clientHeight` → `0`
- `getComputedStyle(el).width` → 設定値 (例: `"375px"`) は返るが auto / 100% 等は計算されない

Tailwind の `sm:w-[375px]` のようなレスポンシブ幅は、jsdom 上では実際に 375px に「縮まらない」ため、サイズベースのアサーションは原理的に成立しない。

## Why

jsdom は仕様上「軽量で速い HTML/DOM/JS 実装」を目指しており、レイアウトエンジン (Blink/Gecko の layout phase 相当) を持たない。Canvas を持たないのと同じ理由で、jsdom 単体では CSS によるサイズ計算は走らない。

Playwright/Puppeteer/Chrome for Testing のような実ブラウザ環境では実計算される。

## How to apply

サイズ・位置・レスポンシブ挙動の検証には以下の戦略を使う:

1. **設計時に「サイズアサーション」を仕様化しない** ことを優先
   - Architect は「width === 375px」のような仕様を Reviewer 用挙動に書かない
   - 代わりに「`<MobileFrame>` 要素に `data-testid="mobile-frame"` がある」「Tailwind class `sm:w-[375px]` を持つ」など DOM 構造ベースで仕様化する

2. どうしてもサイズ検証が必要なら **vitest browser mode** (`@vitest/browser` + Playwright) または Playwright 単体の E2E に切り出す

3. テスト側で妥協する場合: `el.className.includes("w-[375px]")` のようなクラス名検証 (実装詳細結合だが、設計が CSS class まで指定しているなら許容)

4. レビュー時、サイズ検証の仕様が落ちてきたら **Reviewer は GREEN 判定の前にリーダーへ「これは jsdom で検証不能、設計から削るか E2E 化するか」を上申** する

## Related

- `Muraki/knowledge/gotcha/vitest-expo-rn-import-pitfalls.md` (Vitest + jsdom 周りの別ハマり)
