---
title: Vitest の jsdom 環境で localStorage が未提供 (setItem is not a function)
category: gotcha
tags: [vitest, jsdom, testing-library, localStorage, theme, web-storage]
created: 2026-06-08
project: kinketsu-taisaku
sources:
  - "kinketsu-taisaku .designs/20260608-ui-cloudflare-redesign.md §4 useTheme / §10 テスト基盤"
---

## Context

CF風 UI 再設計 (kinketsu-taisaku) の Reviewer 検証。`useTheme` は ThemeMode を
localStorage (`kt-theme`) に永続する設計 (§4)。jsdom 25.0.1 + Vitest 4.1 +
`environment:"jsdom"` (globals:true、environmentOptions 未設定) で useTheme / ThemeToggle /
ThemeToggle を内包する AppShell を render すると `window.localStorage.getItem is not a function`
/ `localStorage.setItem is not a function` で落ちた。

## What

この構成では **jsdom が Web Storage (localStorage/sessionStorage) を提供しない**。
最小再現:
```ts
it("ls", () => { localStorage.setItem("x","1"); }); // TypeError: setItem is not a function
```
既存 32 件は localStorage を使わないため非破壊。新規にテーマ永続テストを足した瞬間に顕在化した。
これは実装バグでも設計の曖昧さでもなく **テスト環境 (jsdom storage) の欠落**。

## Why

jsdom の localStorage は origin に紐づく。Vitest の jsdom 環境では url 設定や jsdom の
ビルドによって Web Storage 実装が無効 / 未バンドルになることがあり、`window.localStorage` が
存在しないか opaque origin で SecurityError になる。`vitest.config.ts` で
`environmentOptions.jsdom.url` を設定 or setupFile で polyfill するのが本筋だが、
config 変更が禁止されている (既存テスト DB の fileParallelism 制約を壊さないため) 状況だと
config に触れない。

## How to apply

- **Reviewer (config に触れない場合)**: テストファイル内 `beforeAll` で最小 localStorage を
  注入する。`window` と `globalThis` 両方に `Object.defineProperty` で配ると、実装が
  `localStorage` でも `window.localStorage` でも読めて確実:
  ```ts
  beforeAll(() => {
    let store: Record<string,string> = {};
    const ls = {
      getItem:(k:string)=>k in store?store[k]:null,
      setItem:(k:string,v:string)=>{store[k]=String(v);},
      removeItem:(k:string)=>{delete store[k];},
      clear:()=>{store={};},
      key:(i:number)=>Object.keys(store)[i]??null,
      get length(){return Object.keys(store).length;},
    };
    Object.defineProperty(window,"localStorage",{configurable:true,value:ls});
    Object.defineProperty(globalThis,"localStorage",{configurable:true,value:ls});
  });
  ```
  これは「実装に合わせたテスト」ではなく**環境の欠落補完**なので検証機能を損なわない。
- **Architect / プロジェクト基盤**: localStorage を使う機能を Reviewer に検証させるなら、
  設計 doc の「テスト基盤」に setupFile (例 `tests/setup.ts`) で storage polyfill を
  仕込む方針を書くか、`vitest.config.ts` の `environmentOptions:{jsdom:{url:"http://localhost"}}`
  を指定しておく。そうすればテストごとの in-file polyfill が不要になる。
- matchMedia も jsdom 未提供。テーマ auto / OS 追従を検証するなら同様に stub が要る
  ([[pattern/theme-auto-resolve-data-theme-matchmedia]])。matches 可変 + change を
  手動 dispatch できる MediaQueryList 風 stub にすると auto ライブ更新まで検証できる。
