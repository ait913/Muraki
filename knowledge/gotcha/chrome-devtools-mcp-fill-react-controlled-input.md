---
title: chrome-devtools MCP の fill は React controlled input の onChange を発火させない
category: gotcha
project: global
tags: [chrome-devtools-mcp, react, testing, e2e, controlled-input]
created: 2026-05-26
sources:
  - 実体験: omatase-demo 実機検証で CreateGroup form の表示名 input が反応しなかった
---

## Context

`mcp__chrome-devtools__fill` (またはツール呼び出し名 `fill`) で React の controlled input (`<input value={state} onChange={...} />`) に値を入れて、続けて submit ボタンを click した場合、**form submit が trigger されない / button が `disabled` のまま見える**。

実例: `omatase-demo` の `/create` で `useState("")` を使った表示名 input。MCP `fill` で「たんり」と入れて click すると、a11y snapshot 上は `value="たんり"` だが React state は `""` のまま → `disabled={!guestName.trim()}` が真のままで submit されない。

## What

`fill` は DOM input の `value` 属性を直接書き換えるが、React 19 の controlled input は **synthetic event 経由の onChange でしか state 更新しない**。MCP の fill は DOM property setter を bypass するが、React の `inputValueTracker` が現在値を「変更なし」と判定して onChange を suppress する。

a11y tree / DOM 上は値が見えても、**React state は古いまま**。`disabled` 評価や form の controlled input 全体が古い state を参照する。

## Why

React の controlled input は内部で `HTMLInputElement.prototype` の value setter を hijack して、setter 呼び出しを onChange dispatch に紐付ける。Puppeteer 系の `element.value = "..."` だとこの hijack を発火させず、`input.dispatchEvent(new Event("input", { bubbles: true }))` を別途呼ぶ必要がある。chrome-devtools MCP の `fill` は前者の挙動。

参考: https://github.com/facebook/react/issues/11488

## How to apply

E2E や実機検証で React controlled form を操作するとき:

**A 案 (推奨): API 直叩きで状態を進める**
- `mcp__chrome-devtools__evaluate_script` で fetch を叩いて、必要な server state (sign-in / 作成 / 編集) をスクリプトで作る → navigate で目的画面に進む
- form 経由を回避する。実機での「最終 UI 表示」だけ確認したい場面に最適

**B 案: evaluate_script で React 互換の value setter を呼ぶ**

```js
mcp__chrome-devtools__evaluate_script({
  function: `(el) => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
    setter.call(el, "たんり");
    el.dispatchEvent(new Event("input", { bubbles: true }));
  }`,
  args: ["<uid of input>"]
})
```

**C 案: type_text で 1 文字ずつ送る**
- `mcp__chrome-devtools__type_text` は keydown/keyup を発火させるので、React の synthetic event handler が動く可能性が高い (未検証)
- 検証コスト > A 案

**D 案: ユーザーに手動操作してもらう**
- 実機 (人の指) では問題ないので、検証の本質が「人が触れるか」なら最も確実

「フォーム submit が動かない」を見たら、まず **A 案 (API 直叩き)** に切り替えるのが時間効率最大。 MCP の fill は **表示確認専用**と捉えて使い分ける。

## 関連

- [`tool-quirk/chrome-for-testing.md`](../tool-quirk/chrome-for-testing.md) — Chrome for Testing の運用全般
