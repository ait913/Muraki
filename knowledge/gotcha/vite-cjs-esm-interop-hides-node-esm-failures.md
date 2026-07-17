---
title: Vitest の CJS/ESM interop は Node より寛容 — interop バグは in-process テストでは原理的に検出できない
category: gotcha
tags: [vitest, vite, esm, cjs, interop, node, test-blind-spot, negative-control, tsx]
created: 2026-07-17
project: atender
sources:
  - atender fix/ics-esm-import (f4160c2) レビュー実測
  - apps/api/tests/ics-esm-interop.test.ts
---

## Context

atender の ICS インポート (`POST /api/rooms/:id/ics-imports`) が本番・dev で**一度も動いたことがなかった**。
常に `{"error":{"code":"INVALID_ICS","message":"ical.parseICS is not a function"}}`。
原因は CJS パッケージ (`node-ical`) の名前空間インポートで `parseICS` が undefined になる CJS/ESM interop。

レビューで挙動仕様からブラインドテストを 5 本生成 → 全 pass。
**負のコントロール** (`git checkout f4160c2^ -- src/lib/icsParse.ts` で修正前に戻す) を取ったところ、
**修正前のコードでも 5/5 GREEN のまま**だった。テストは緑だが何も検証していなかった。

## What

**Vite/Vitest はソースを自前の transform パイプラインに通し、Node より寛容な CJS↔ESM interop を適用する。**
そのため「CJS パッケージを名前空間インポートすると壊れる」類のバグは、
**Vitest の in-process テストでは再現しない**。同一ファイルが:

| ローダ | 修正前コード | 実測 |
|---|---|---|
| Vitest (Vite transform) | **動く** | 5/5 GREEN (偽) |
| `tsx` / `node dist/` (Node native ESM) | **壊れる** | `ical.parseICS is not a function` |

dev (`tsx watch`) も本番 (`node dist/`) も**後者**を使う。
→ **Vitest スイートが全緑のまま、機能が本番で 100% 壊れて出荷される。**
atender の ICS インポートは実際にこの状態で出荷されていた (テストが無かったのではなく、**テストがあっても無駄だった**)。

さらに悪いことに、修正前は **valid な ICS でも garbage な ICS でも等しく 400 `INVALID_ICS`** を返す。
「不正な ICS は 400」を status だけで assert するテストは**壊れたコードでも通る**。
「機能が一度も動いたことがない」バグは vacuous test を量産しやすい。

## Why

- Vite は依存を `optimizeDeps` / esbuild で prebundle し、CJS を ESM に変換する際に **interop shim** を挟む。
  名前空間オブジェクトに `module.exports` のプロパティを展開してくれるので `ns.foo()` が通る。
- Node の native ESM は CJS を読むとき **`default` に `module.exports` 全体を載せる**のが基本で、
  名前付き/名前空間経由のアクセスは cjs-module-lexer が静的に検出できた範囲に限られる。
  検出漏れすると `ns.foo` は undefined → `is not a function`。
- つまり**テストランタイムと本番ランタイムでモジュール解決の意味論が違う**。
  in-process テストは「Vite で動くか」しか測れず、「Node で動くか」を**原理的に**測れない。

## How to apply

- **CJS パッケージを使う箇所の interop は、Vitest の in-process テストで担保したと思ってはいけない。**
  対象例: `node-ical`, `rrule`, `jschardet`, `iconv-lite` など CJS/dual package。
- **子プロセスで実ローダを起動する probe テストを 1 本置く。** これが唯一この層を見られる:
  ```ts
  // tests/ics-esm-interop.test.ts
  const stdout = execFileSync(path.join(apiRoot, "node_modules/.bin/tsx"), [probeFixture], {...});
  expect(stdout).not.toMatch(/is not a function/i);
  expect(stdout).toContain("PROBE_OK");   // 「throw しない」でなく実値まで見る
  ```
  fixture 側は本番と同じ import 経路で対象モジュールを呼び、`PROBE_OK`/`PROBE_THREW` を stdout に出すだけ。
  atender 実測: 修正前 → この 1 本だけが RED、in-process 5 本は GREEN。
- **バグ修正レビューでは負のコントロールを必ず取る。**
  「テストが緑になった」は**修正が効いた証拠にならない**。
  修正前コードに戻して**赤くなることを確認**して初めてテストが検証として機能する。
  ここでは負のコントロールが無ければ「GREEN、修正 OK」と誤報告していた。
- **CI/本番との差はテストランタイムに限らない。** 同レビューで TZ も同型の穴だった
  (dev=JST / `node:20-alpine` 本番=UTC。gotcha 参照: ics-all-day-floating-date-depends-on-server-tz)。
  「手元で緑」は「本番の設定で緑」を意味しない。
