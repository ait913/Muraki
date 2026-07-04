---
title: segmented/enum の value キー名 (英字 testid) を設計が一部しか例示しないと Reviewer が推測して fail
category: gotcha
tags: [design-doc, data-testid, segmented, enum, render-test, architect, reviewer]
created: 2026-06-11
project: kinketsu-taisaku
sources:
  - Muraki/projects/kinketsu-taisaku/DESIGN.md (§3.1 / §6 Pass①)
  - Muraki/worktrees/kinketsu-taisaku-ds (design-system-pass レビュー)
---

## Context

DESIGN.md §3.1 で `<select>` を segmented ボタン群に全置換し、testid 規約を
`segment-<field>` (群) / `segment-<field>-<value>` (各 option) と定めた。
§6 Pass① 注記で例示したのは `segment-paid-paid` / `segment-paid-not` /
`segment-sign-income` の 3 つだけ。

「有効/停止」segmented の停止 option の `<value>` 英字キーが
`stopped` か `inactive` か `off` かは設計に明記が無かった。

- 設計の確定事項: 群は radiogroup、ラベルは「有効」「停止」、初期選択が
  `aria-pressed=true`、別 option tap で入替、select 不在
- 設計が未確定: 停止 option の testid value 名

Reviewer (Codex) は `segment-active-stopped` と推測してテストを書き、
実装は `segment-active-inactive` を出力 → testid 不一致で fail。
DOM 自体 (radiogroup / aria-pressed 入替 / ラベル / select 不在) は設計通り。

## What

列挙値 (確定/未確定、有効/停止、収入/支出/自由) の **日本語ラベルは設計に
書いてあるが、testid やコード上の英字 value キーは一部しか例示されない**。
Reviewer がその英字キーを決め打ちすると、実装が別の英字を選んでいて fail する。
これは実装バグでなく「設計の曖昧さ + テストの過剰仮定」。

error code の例示 vs 規約問題 ([[gotcha/design-spec-implicit-vs-explicit-error-codes]])
の UI 版。根本原因は同じ「設計の列挙が網羅規約か例示か曖昧」。

## Why

- 設計で全フィールドの全 value 英字キーを列挙するのは冗長で、Architect は
  代表例だけ書きがち
- 日本語ラベルは UX 要件なので必ず書くが、英字 value はコード詳細扱いで漏れる
- Reviewer は設計を正典とするので「例示された命名規則」から残りを推測する →
  実装者の命名裁量とズレる

## How to apply

### Reviewer 側 (推奨パターン)

segmented / radio group の挙動検証は **英字 value testid を決め打ちしない**。
設計で確定しているもの (群 testid・日本語ラベル・aria-pressed 挙動) で取得する:

```ts
const group = within(sheet).getByTestId("segment-active"); // 群は規約で確定
const enabled = within(group).getByText("有効");   // ラベルは設計 §3.1 で確定
const stopped = within(group).getByText("停止");
expect(enabled).toHaveAttribute("aria-pressed", "true");
await user.click(stopped);
expect(stopped).toHaveAttribute("aria-pressed", "true");
expect(enabled).toHaveAttribute("aria-pressed", "false");
```

群 testid (`segment-<field>`) と select 不在 (`querySelector("select")===null`) と
aria-pressed 入替が設計の本質。個別 option の英字 value は実装裁量に委ねる。
設計が `segment-sign-income` のように明示例示した value は testid で取ってよい。

### Architect 側

segmented を導入する設計では、testid 規約の例示直後に
「value 英字キーは <list>。例示外は実装裁量」または
「全 value を列挙」のどちらかを明記する。日本語ラベルだけでなく英字キーの
網羅性を意識する。

### 切り分け

testid 不一致だけで DOM 挙動 (aria-pressed/ラベル/select 不在) が設計通りなら
**実装バグでなく設計の曖昧さ**。テストを設計の確定線に寄せて GREEN にしてよい
(実装を設計に寄せる必要はない)。
