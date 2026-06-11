---
title: Modal/Sheet を基底コンポーネント化して overlay/ESC/× の 3 経路 close を強制する
category: pattern
tags: [ui, modal, bottom-sheet, accessibility, react, tailwind, design-system]
created: 2026-05-27
project: global
sources:
  - https://m3.material.io/components/bottom-sheets/guidelines
  - https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/
  - https://developer.apple.com/design/human-interface-guidelines/sheets
---

## Context

OMATASE-demo 実機検証 (Touri, 2026-05-26) で「モーダルは空白部分タップで戻れるようにして欲しい。全体的に」という体感悪化 fb が出た。原因は **各モーダル/Sheet 個別実装** で close 経路が個別判断されており、ある Sheet では overlay tap 不可、ある Sheet では ESC 不可、というばらつき。

設計レビュー時に「全モーダルで overlay tap close 必須」と書いても、個別実装者は忘れる/解釈ブレる。設計強制力が弱い。

## What

`<Modal>` / `<Sheet>` を **基底コンポーネント** として最初に切り出し、全てのモーダル系 UI (ScheduleEditSheet / FeatureCatalogSheet / LocationPickerSheet / ShareSheet / …) は基底を using する設計にする。基底に **3 経路 close を内蔵**:

1. **overlay (背景 dim layer) tap** → onDismiss
2. **ESC キー** (window keydown listener) → onDismiss
3. **右上 × ボタン** (`data-testid="sheet-close"`、44pt 以上) → onDismiss

3 経路すべて同じ `tryDismiss()` → `dismissConfirm` → `onDismiss` 経路を通す。個別 Sheet は close を実装しない。

```tsx
interface SheetProps {
  open: boolean;
  onDismiss: () => void;
  title?: string;
  rightAction?: { label: string; onClick: () => void };
  dismissConfirm?: () => boolean | Promise<boolean>;  // 未保存変更時の "破棄しますか?"
  stackLevel?: 1 | 2;        // Sheet on Sheet 用 z-index
  children: React.ReactNode;
}
```

合わせて:

- focus trap (Tab で内部循環)
- body scroll lock (open 中 `overflow:hidden`)
- z-index: stackLevel=1 → 1099/1100、stackLevel=2 → 1109/1110 (leaflet/外部の上に確実に乗る)
- DOM 構造 (`data-testid` 含む) を固定し、Reviewer がテストで 3 経路をまとめて 1 セット assert すれば全 Sheet がカバーされる

## Why

- **規約の自然強制**: 「全 Sheet で overlay tap close を実装すること」というドキュメント規約は陳腐化する。**実装単位を 1 箇所に集約**することで規約が物理的に守られる
- **テストコストの圧縮**: 3 経路 × N 個の Sheet を個別 assert すると N 倍。基底 1 セットだけテストし、個別 Sheet は「内部で `<Sheet>` を using しているか」だけを検証すれば十分
- **未保存変更 confirm の統一**: `dismissConfirm` を props で渡せば各 Sheet (フォーム持ち) で独自 confirm 経路を書かずに済む。3 経路すべて同じ confirm を通る
- **Sheet on Sheet 対応**: `stackLevel` を Props で持つと z-index 計算が一箇所に閉じる。leaflet との衝突も基底側で吸収可能

## How to apply

新規プロジェクト立ち上げ時、最初に `<Modal>` / `<Sheet>` 基底を切り出してから個別 Sheet を作る。チェック:

- [ ] 基底コンポーネント (`Modal.tsx` / `Sheet.tsx`) が `src/client/components/` 直下にある
- [ ] overlay/ESC/× の 3 経路すべて同じ `tryDismiss` → `dismissConfirm` → `onDismiss` を通る
- [ ] focus trap + body scroll lock を基底側で
- [ ] z-index は基底側で stackLevel 制御 (個別 Sheet に z-class を書かない)
- [ ] テストは基底に対して 3 経路 + confirm + stack を網羅、個別 Sheet では再検証しない
- [ ] DOM 構造を固定 (`data-testid="sheet-overlay"` / `"sheet"` / `"sheet-close"` / `"sheet-action"`)
- [ ] 設計 doc には「全 Sheet は内部で `<Sheet>` を using する」を**規約として明示**

逆にやってはいけない:

- 個別 Sheet が onClick={onClose} を直接書く (×) → 基底 prop に逃がす
- overlay の `bg-black/40` をベタ書きで個別 Sheet に置く → 基底に集約
- stackLevel を z-class で個別に上書きする → 基底 prop でしか変えられないようにする

OMATASE-demo の §3.6 / §12.13 / §7.12 はこのパターンを設計に直接埋め込んだ実例。
