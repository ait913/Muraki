---
title: codex exec をバックグラウンド/パイプ起動するときは `< /dev/null` で stdin を閉じる
category: tool-quirk
project: global
tags: [codex, codex-exec, background, stdin, hang, developer-agent]
created: 2026-06-11
sources:
  - developer (Codex) 召集で約30分ハングを実踏 (2026-06-11)
---

## Context

`codex exec <prompt>` を**バックグラウンド**や**パイプ** (`2>&1 | tail` 等) と組み合わせて起動すると、codex が `Reading additional input from stdin...` で**無限ハング** (数十分。セッションログも生成されず git も無変化) することがある。

## What

- パイプやバックグラウンド起動で **stdin が TTY でなく開いたまま**になると、codex は positional の prompt 引数でなく **stdin からの追加入力待ち**に入ってしまう。
- 結果、プロンプトを渡しているのに何も実行せず固まる。タイムアウトまで気付きにくい (出力も差分も出ない)。

## Why

codex exec は引数 prompt があっても、stdin が「読める状態 (パイプ/リダイレクト未指定)」だと追加入力を読もうとする実装。バックグラウンド (`&`) やパイプ接続で stdin が閉じられていないと待ち続ける。

## How to apply

`codex exec` をバックグラウンド/パイプで起動するときは **必ず `< /dev/null` を付けて stdin を閉じる**:

```sh
codex exec "<prompt>" < /dev/null 2>&1 | tail -n 50 &
```

- フォアグラウンドの対話 TTY 起動では不要 (TTY は EOF を返す)。
- ハング検知: 起動後しばらくして git 差分もログも無いまま無反応なら stdin 待ちを疑い、kill して `< /dev/null` 付きで再起動する。

## 関連
- [[tool-quirk/codex-cli-imagegen-tool]] — codex CLI の他の癖
