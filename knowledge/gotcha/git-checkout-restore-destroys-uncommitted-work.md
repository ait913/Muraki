---
title: 負のコントロールの復元に git checkout -- を使うと、レビュー対象の未コミット作業を消す
category: gotcha
tags: [git, worktree, negative-control, mutation-testing, reviewer, restore]
created: 2026-07-17
project: global
sources:
  - atender feature/ui-revamp-p1 の Reviewer レビュー (2026-07-17) — 実際に project.yml の Developer 変更を消した
  - Muraki/knowledge/gotcha/mutation-must-be-proven-to-reach-all-sites.md (変異の作法)
---

## Context

Reviewer が負のコントロール (mutation testing) を回すとき、対象ファイルを一時的に壊して
テストが赤くなるかを見る。壊したら必ず元に戻す必要がある。

Muraki の Reviewer は **Developer が作業した直後の worktree** を受け取る。
このとき対象ファイルは **未コミットの変更を持っている** (`git status` が ` M` を出す状態)。

## What

**`git checkout -- <path>` は「変異前の作業ツリーの状態」でなく「HEAD の状態」に戻す。**
未コミットの変更を持つファイルに撃つと、**Developer の実装ごと消える。**

atender P1 で実際に起きた。`project.yml` から `developmentLanguage: ja` を外す変異
(設計 §10.1 が名指しで要求する負のコントロール) を撃ち、`git checkout -- project.yml` で戻したところ:

- `developmentLanguage: ja` (Developer が追加) → **消えた**
- `UIAppFonts` の Inter/Noto 6 件削除 (Developer が実施) → **7 件に戻った**

`git checkout` は成功し、エラーも警告も出ない。**変異を戻したつもりで、feature ごと戻していた。**
気付けたのは復元直後に `grep -c developmentLanguage` が `0` を返したからで、
そのまま「復元済み」と報告してテストを回していれば **#S1/#S2/#S3 が赤いまま「実装バグ」と誤帰属**していた。

## Why

`git checkout -- <path>` の意味は「index (無ければ HEAD) の内容で作業ツリーを上書きする」であって
「直前の状態に戻す」ではない。**git は変異前の作業ツリーを覚えていない** — 未コミットの変更は
git にとって「まだ存在しない情報」であり、上書き対象でしかない。

罠なのは、この手順が**ファイルがコミット済みでクリーンなときは正しく動く**こと。
`git show <merge-base>:<file> > <file>` → テスト → `git checkout -- <file>` は、
**元のファイルが未変更のときにだけ**成立する。Reviewer が触るのは大抵その逆の状況なので、
「前回うまくいった手順」がそのまま事故になる。

## How to apply

**変異の復元は `cp` バックアップ → `diff` / `md5` でバイト単位に検証する。git に頼らない。**

```sh
BK=/tmp/scratch/target.orig
cp <target> $BK                      # 変異前に必ず取る
# … 変異 → テスト …
cp $BK <target>                      # 復元
diff $BK <target> ; echo "exit=$?"   # 0 でなければ復元できていない
```

- **`git status` で ` M` が付くファイルに `git checkout --` を撃たない。** 撃つ前に `git status --short <path>` を見る
- 復元後は**復元自体を証明する**: 全テストを回して変異前と同じ件数・同じ結果になることを確認する
  (atender では復元後に 259/259 green を再現して初めて「戻った」と言えた)
- 事故ったら **HEAD 版に対する差分を人手で復元できる**。そのためにも変異前に
  対象ファイルを一度 `cat` して**会話ログに残しておく**と保険になる (実際これで復元できた)
- `git stash` も同様に危険 (変異と Developer 変更を区別せず両方畳む)。使うなら変異前に stash push
