---
title: Markdown を正典にしたリッチエディタ — 保存は「不動点まで回した正規形」、照合は revision
category: pattern
tags: [markdown, tiptap, prosemirror, editor, normalization, autosave, optimistic-concurrency, mcp]
created: 2026-10-05
project: global
sources:
  - projects/wasawasa/.designs/20261005-pages-markdown-docs.md
  - projects/wasawasa/.knowledge/research-doc-editor.md
---

## Context
wasawasa Phase 3b (ページツリー + Notion 風エディタ + MCP で AI が読み書き) の設計で、`body_md` を正典にした。研究は Tiptap 3 + `@tiptap/markdown` の往復を「冪等」と報告していたが、それは 2 つの小さなサンプルでの話だった。Muraki 配下の実 Markdown 669 本で回し直すと前提が崩れた。

## What
- **「parse → serialize 1 回 = 正規形」は成り立たない。** 実文書では 2〜3 回目でやっと止まるものがあり、止まらないもの (回すたびにエスケープが `\`` → `\\\`` と増える、コードの字下げが 1 ずつ増える) もある。保存のたびに本文が変わり、エディタで開くたびに差分が出て自動保存が空振りし、偽の衝突になる
- 正規化は **最大 4 回回して最初に一致した出力 (不動点) を保存し、一致しなければ 422 + 行番号** にする。1 回だけ・最後の出力を保存、はどちらも壊れる
- サーバーの正規化は **エディタと同じ拡張セットを import した DOM 無しの `MarkdownManager` + `getSchema` + `nodeFromJSON`** で足りる (jsdom 不要)。`node.check()` は呼ばない (エディタも呼ばないので、check で弾くとエディタが受け入れる文書を拒否する)。不変条件「保存済み s をエディタに読ませて `getMarkdown()` すると s」を実ブラウザで確かめる
- 不動点を壊していた原因は 2 つ: (A) `@tiptap/extension-list` 3.31.4 の番号付きリストのパーサが続き行から削る字下げを 1 文字少なく計算する (`indentLevel + marker.length + 1` → `line.length - content.length` に pnpm patch)、(B) リスト項目内で閉じフェンス直後に空行なしで続く段落が文字扱いになる (前処理で閉じフェンスの後に空行を挟む。Tiptap は tight/loose を区別しないので構造は変わらない)。2 つ直して 669 本中 666 本が 3 回以内に収束
- `@tiptap/markdown` の parse は文書の形で 2 乗に伸びる (短いブロックが大量に並ぶ合成文書で 200 KB = 1.3 秒/回)。正規化は複数回 parse するので、1 ページの上限は「最悪形 × 回数」でイベントループが許容できる大きさ (256 KiB) で決める。jsdom 上のエディタは実ブラウザの数百倍遅いので、jsdom テストは小さい fixture に限る
- 衝突検出は `updated_at` でなく整数 `revision` (タイトルと本文が変わった時だけ +1、移動・ゴミ箱では変えない)。**送った内容が現在値と同じなら revision が古くても 200 (変更なし)** にすると、応答を失った自動保存の再送が自分の保存と衝突しない
- 自動保存の監査 Event は「同じ人・同じページ・10 分以内・間に別の Event が無い」なら直前の行を UPDATE してまとめる (通知対象から外した kind に限る)

## Why
ProseMirror の木と Markdown は 1:1 ではなく、serializer と parser がそれぞれの近似で書かれているので、往復の合成は恒等にならない。正典をテキストに置く以上、「どの経路で書いても同じ文字列になる」ことを 1 つの関数 (サーバー) に集め、その関数の出力が自分自身の不動点であることを保証しないと、経路間の表記ゆれが差分・衝突・内容の劣化として表に出る。

## How to apply
- Markdown (や他のテキスト正典) をエディタで編集させる設計では、正規化関数を 1 つにしてサーバーで全書き込みに通し、**不動点まで回す + 回らなければ拒否** を仕様にする。不変条件 (冪等 / エディタ不動点 / エディタ出力の受理) を挙動仕様に書き、Reviewer がそのまま unit にできる形にする
- ライブラリの往復性は **研究のサンプルでなく実コーパス (手元の Markdown 数百本) で回してから** 設計に書く。止まらない形は最小再現を作り、上流の 1 行パッチか前処理で潰せるかを見る
- 正規化の負のコントロール (パッチを外す / 前処理を恒等にする → 特定の unit が赤) を実装ゲートに入れる
- 上限サイズは実文書の平均ではなく最悪形の計測で決める
