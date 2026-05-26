---
title: モバイル first PWA の bottom tab bar 実装ベストプラクティス (2025-2026)
category: pattern
project: global
tags: [mobile, pwa, bottom-tab, safe-area, ios-hig, material-3, wcag]
created: 2026-05-15
sources:
  - https://developer.apple.com/design/human-interface-guidelines/tab-bars
  - https://m3.material.io/components/navigation-bar/guidelines
  - https://m3.material.io/components/navigation-bar/specs
  - https://m3.material.io/components/floating-action-button/guidelines
  - https://web.dev/articles/designing-for-the-notched-display
  - https://developer.mozilla.org/en-US/docs/Web/CSS/env
  - https://developer.mozilla.org/en-US/docs/Web/API/VisualViewport
  - https://developer.chrome.com/blog/viewport-resize-behavior/
  - https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html
---

## Context

モバイル first Web アプリ (PWA / Capacitor / SwiftUI 移行予定 SPA) で、下端 bottom tab bar を実装するときの 2025-2026 BP。Atender redesign 調査でまとめ。

## What

### 1. タブ数 = 3-5 個

- iOS HIG / Material Design 3 共通推奨
- 2 以下は tab ではなく segmented control が適切
- 6 以上は「More」格納 (iOS) / drawer 切替 (MD3)

### 2. アイコン + ラベル両方表示

- アクセシビリティ・発見性の両方で必要
- MD3 では active のみラベル表示パターン (Selected-only) も許容だが、全表示推奨
- 簡潔な名詞 (動詞ではなく)、2-5 文字

### 3. アクティブ状態の表現

| パターン | 採用例 |
|---|---|
| 塗りつぶしアイコン (`fill`) + ラベル色変化 | iOS SF Symbols |
| ピル型背景 (Active Indicator) | Material Design 3 |
| 上部 2px indicator bar | Web カスタム |
| 動的 accent color | ブランドカラー利用 |

主流: アイコン fill 切替 + ラベル太字 / ピル背景のいずれか。

### 4. タッチターゲット

- 最小 44pt (iOS) / 48dp (Android)
- WCAG 2.2 `target-size-minimum` は 24x24px 以上
- 推奨: タブ全体の高さ 48-56px

### 5. safe area 対応 (notch / home indicator)

```css
.bottom-tab {
  position: fixed;
  bottom: 0;
  width: 100%;
  padding-bottom: env(safe-area-inset-bottom);
  background: var(--bg-card);
}
```

- viewport meta に `viewport-fit=cover` 必須
- `env(safe-area-inset-bottom)` で iPhone home indicator を避ける
- 背景色は safe-area 全体を塗る (透明だと OS UI と被って読みにくい)

### 6. 仮想キーボード問題 (iOS Safari)

- `position: fixed` 要素はキーボード表示時に浮き上がる事故
- 対策 A (簡易): 入力フォーカス時に bottom tab を `display: none`
- 対策 B (堅牢): Visual Viewport API でキーボード高さを検知、tab の位置を維持
- Chrome: `<meta name="viewport" content="interactive-widget=resizes-content">` で自動調整

### 7. FAB との併用

- bottom tab + FAB は MD3 で許容
- FAB は bottom tab の「上」に配置、または中央タブと統合 (Bottom App Bar)
- 主要アクションが特定タブ依存ならタブ内 CTA で代替推奨、FAB は冗長になりがち

## Why

- 親指リーチ (片手操作) の届きやすい下端配置は片手操作率 75% (2025 統計) で必須
- iOS HIG / MD3 のガイドラインが似通っているため、両プラットフォームで同じ UX を組める
- safe area 対応がないと iPhone X 以降 (2017+) で home indicator にコンテンツが食われる
- 仮想キーボード問題は最初に踏まないと iPhone Safari で「タブが画面中央に浮く」奇怪な挙動になる

## How to apply

新規モバイル first Web で:

1. **タブ 3-5 個**で機能を分類、6 個以上にしない (More 格納は最後の手段)
2. **アイコン + ラベル両方**、ラベルは 2-5 文字の簡潔な名詞
3. **`env(safe-area-inset-bottom)` を最初から入れる**、viewport meta に `viewport-fit=cover`
4. アクティブ状態は **fill アイコン + ラベル太字** がプラットフォーム横断で安全
5. 入力フォームを持つ画面では bottom tab を一時非表示にする (iOS Safari 浮き上がり回避)
6. PC (≥768px) では bottom tab を **left sidebar 化** (240px 幅)。CSS media query 1 個で切替

逆に**やらない**:
- アイコンのみ / ラベルのみ (片方欠ける UI は学習コスト上昇)
- 6 個以上のタブ (タップ精度低下、視覚過負荷)
- safe area 対応の後回し (リリース後に気づくと手戻り)
- FAB を bottom tab の真上に置く (タッチ干渉、MD3 違反)

## 反例 / 限界

- タブ 1 つに過剰な機能を詰め込むと「More」相当が画面内に発生し、bottom tab の意味が薄れる
- 横画面 (landscape) では bottom tab が画面の 1/4 を占める。横画面サポート要件があるアプリでは sidebar 化を検討
- 出席記録のような「複数アクションを 1 画面で完結」したい場面では、bottom tab + sticky CTA (bottom tab の真上 60-80px の固定ボタン) の組み合わせが有効
