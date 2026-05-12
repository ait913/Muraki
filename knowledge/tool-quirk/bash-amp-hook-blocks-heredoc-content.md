---
title: block-bash-amp.sh は heredoc/tee 内のコード文字列の論理積もブロックする
category: tool-quirk
tags: [bash, hook, heredoc, claude-code]
created: 2026-05-10
project: global
sources:
  - ~/.claude/hooks/block-bash-amp.sh
---

## Context

Muraki ルートに置かれた `block-bash-amp.sh` フックは、
Bash ツールで実行する command 文字列に bash の論理積演算子が含まれているとブロックする。
複合コマンドの permission 判定が分割できないため。

## What

`tee file > /dev/null <<'EOF' ... EOF` のように heredoc でコードを書き出す時、
heredoc の中身に TypeScript/JavaScript の論理積 (アンパサンド2連) が含まれていても
フックがブロックする。フックは command 文字列全体を grep するだけで、
heredoc の境界を解釈しない。

例: テストコード `if (value !== null A typeof value === "object")` (A = アンパサンド2連) を
含む heredoc は弾かれる。

## Why

- bash hook は単純文字列マッチで実装されているため境界認識ができない
- echo / cat / tee いずれも同じ
- このナレッジ自身、説明文に該当文字を書いただけでブロックされた

## How to apply

1. heredoc 内のコードに論理積を書きたい場合、ロジックを分割する
   - 複合条件 `if (a A b) {...}` を `if (a) { if (b) {...} }` のように early return / nested if 化
2. Edit ツール (Write) を使うほうが安全
3. Reviewer/Developer ともに、テストや実装ファイルを heredoc で生成する時に注意
4. このナレッジ自体を編集する時も、論理積文字列を直接書くと弾かれる点に注意
