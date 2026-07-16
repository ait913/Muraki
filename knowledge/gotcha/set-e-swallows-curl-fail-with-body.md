---
title: set -e + resp=$(curl --fail-with-body) はエラー body をログに出さずに死ぬ
category: gotcha
project: omatase
tags: [curl, bash, github-actions, ci, debuggability, coolify]
created: 2026-07-16
sources:
  - omatase .designs/20260716-coolify-deploy.md (D2)
  - Reviewer 実測 (2026-07-16, 旧実装 775c08d と新実装 e9ae198 の突合)
---

## Context

CI の step で外部 API を叩き、失敗時に**レスポンス body をログに残したい**とき。
`curl --fail-with-body` は「非 2xx なら exit 22、ただし body は stdout に出す」オプションなので、
一見これだけで「失敗を検知しつつ body も残る」ように見える。

## What

`set -euo pipefail` 下で

```sh
resp=$(curl -sS --fail-with-body ... )
echo "$resp"   # ← ここには絶対に到達しない
```

と書くと、**body は `$resp` に捕らえられたまま step が即死する**。
`--fail-with-body` の exit 22 が `set -e` を発火させ、`echo "$resp"` の前にシェルが終わるため。
結果、ログに残るのは `curl: (22) The requested URL returned error: 401` だけで、
**サーバが返した原因説明 (`{"message":"..."}`) は永久に失われる**。

実測 (omatase, 401 を返す fake API):

| 実装                                        | step exit | body がログに出るか |
| ------------------------------------------- | --------- | ------------------- |
| `resp=$(curl --fail-with-body ...)` (旧)   | 22        | **出ない**          |
| `resp=$(curl ...) \|\| rc=$?` + echo (新)  | 1         | 出る                |

「step が赤くなる」ことは両者とも同じなので、**成功/失敗の assert だけでは差が付かない**。
テストは「body 文字列がログに現れること」まで見ないと、この欠陥を検出できない。

## Why

`$(...)` は stdout を変数に捕捉する = その時点では**何も表示されていない**。
`set -e` は「コマンドの exit != 0」で即座に打ち切るので、表示する行に制御が渡らない。
`curl ... | tee` 的に「捕捉しつつ流す」構造でない限り、捕捉と可視化は両立しない。

## How to apply

exit code を退避してから body を出し、明示的に落とす:

```sh
rc=0
resp=$(curl -sS --fail-with-body -H "..." "$URL") || rc=$?
if [ "$rc" != "0" ]; then
  echo "::error::API call failed (curl exit $rc)"
  echo "--- response body ---"
  echo "$resp"
  echo "--- end response body ---"
  exit 1
fi
```

- 接続失敗 (exit 6/7 等) では `$resp` は**空**になる。これは正常 — curl 自身が stderr に理由を出すので、
  body 欄が空でも切り分けは付く。「body が空 = バグ」と判定しないこと
- 設計docに shell 片を書く側 (Architect) は、**「失敗する」だけでなく「失敗の原因がログに残る」まで**を挙動仕様に書く。
  Reviewer はそこを sentinel 文字列で assert できる
- レビュー時は marker (`--- response body ---`) で挟み、**sentinel が marker の内側にある**ことまで見ると確実
