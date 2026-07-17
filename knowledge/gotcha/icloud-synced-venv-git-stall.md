---
title: iCloud 同期下の venv/git が間欠 import・checkout stall する
category: gotcha
project: cross
tags: [icloud, venv, python, import, git, worktree, filesystem, macos]
created: 2026-07-09
sources:
  - "session 2026-07-09-8d4172ed (AgentHub web-dashboard-lp レビュー/マージで発症)"
---

## Context

Muraki の repo は `/Users/touri/Documents/Creatives/Developments/Muraki/...` にある。macOS の `~/Documents` は **iCloud Drive 同期対象**になりうる。iCloud は容量最適化でファイルをクラウドにオフロード(ローカル未実体化)し、read 時にオンデマンドで取得する。この取得が遅い/詰まると、そのファイルへの `read()` syscall がブロックする。

Python の import は site-packages の大量の小ファイルを read するため、iCloud オフロード + 負荷が重なると **`import` が間欠的にハング**する。git の working-tree 一括 checkout/merge も同様に大量 read/write で stall する。

## What

観測した症状(AgentHub の worktree `.venv` と main `.venv` の両方で発症):

- `import agenthub.app` が数十秒ハング。faulthandler で見ると `<frozen importlib._bootstrap_external> get_data`(ファイル read)で停止。
- **素の `from starlette.requests import Request` / `import anyio` が、126 tests を通した既知良好の main `.venv` でもハング**した(=プロジェクトのコード欠陥ではない。環境要因の決定的証拠)。
- ある時点で `import jinja2` は通るのに `import anyio` は詰まる、と**間欠的**(オフロード状態のファイル差)。
- `git merge --no-ff`(45 files の working-tree 書き込み)が2分でタイムアウト(SIGTERM)。`.git/index.lock` 残留 + 部分適用(51 中 13 files だけ書けた不整合)。

## Why

iCloud がオフロードしたファイルの read がブロックするため。venv の site-packages や git worktree のファイルが「クラウドのみ」状態だと、import/checkout がその実体化待ちで固まる。負荷(並行 python プロセス等)が重なると悪化する。

## How to apply

**切り分け(コード欠陥と誤認しないため)**: import ハングを見たら、まず **素のサードパーティ import(`from starlette.requests import Request` 等)を既知良好 venv で試す**。それも詰まるなら環境要因確定 → 実装を疑うのをやめる。faulthandler(`python -X faulthandler -c "import faulthandler; faulthandler.dump_traceback_later(7, exit=True); import ..."`)で `get_data` 停止を見れば disk read stall と分かる。

**回避(テスト実行)**: ソースをローカルディスク(scratchpad `/private/tmp/...`)に `rsync -a`(`.venv`/`.git` 除外)でコピー → そこで `python -m venv` + `pip install -e ".[test]"` → 実行。ローカルディスクなら import 即通。実 Postgres は Docker(iCloud 外)なのでそのまま使える。
- rsync 取りこぼし注意: `__init__.py`/`migrations` が欠けると namespace package 化して import 失敗。コピー後に主要ファイルの存在を確認。

**回避(git マージ)**: working-tree の一括 materialize を避ける。fast-forward 可能なら `git update-ref refs/heads/main <feature-tip>`(**ref だけ進めて working-tree I/O ゼロ**)→ `git reset`(mixed、index 同期)→ 残差分だけ `git checkout -- .`(数ファイル)。`git reset --hard` は破壊的で permission gate に弾かれることがある。`git merge`/`reset --hard` が2分で死ぬ環境では ref 操作に逃がすのが速い。

**恒久策(推奨)**: Muraki の repo・worktree・venv を **iCloud 同期対象外**に置く(`~/Documents` 外に移すか、当該フォルダを iCloud の対象から外す/`.nosync` 運用)。開発中の repo が iCloud 配下にあるのは import/build/git を不安定にするので、そもそも避ける。

**移動作業そのものが別の罠を生む**: iCloud 外へ Finder で移動する際、同名衝突したファイルが「 2」付きで複製され、`.git/refs/` に入ると git が `fatal: bad object` で軒並み落ちる。本書の stall とは別症状なので [[gotcha/icloud-duplicate-files-corrupt-git-refs]] を参照。移動完了直後にツリー全体を掃除すること。

関連: [[gotcha/icloud-duplicate-files-corrupt-git-refs]](同じ根・複製による ref 破損)、[[tool-quirk/chrome-for-testing]](テスト環境の癖)、developer/reviewer は検証を必ずローカルディスク venv で行う(role ノートにも追記済)。
