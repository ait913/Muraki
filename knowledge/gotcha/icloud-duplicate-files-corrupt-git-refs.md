---
title: iCloud/Finder の「 2」複製が .git に湧いて ref を壊す (git が理不尽に落ちる・worktree が勝手に detached)
category: gotcha
project: cross
tags: [icloud, git, refs, worktree, macos, filesystem, detached-head, fsck]
created: 2026-07-17
sources:
  - "session 2026-07-17-24e295f6 (atender で発症。checkout が fatal: bad object で失敗し worktree が detached HEAD に取り残された)"
  - "関連: gotcha/icloud-synced-venv-git-stall.md (同じ根・別症状)"
---

## Context

Muraki の repo は `/Users/touri/Documents/Creatives/Developments/Muraki/...` = macOS の `~/Documents` = **iCloud Drive 同期対象**にあった。同期を OFF にして Finder で iCloud 外へ移動する作業の過程で、**同名衝突したファイルが「 2」サフィックス付きで複製**された。それが `.git` の中にも湧いた。

`icloud-synced-venv-git-stall.md` が扱う **evict/stall (read がブロックしてハングする)** とは別の失敗モード。同じ根から出るが、症状も対処も違う。

## What

`.git` 配下に複製が生まれる。2026-07-17 に Muraki ツリー全体で **17 個**発見:

| 種類 | 例 | 実害 |
|---|---|---|
| **ref の複製** | `atender/.git/refs/remotes/origin/main 2`<br>`tomori/.git/refs/heads/main 2` | **致命的。** git がそのリポジトリで軒並み落ちる |
| index の複製 | `<repo>/.git/index 2` / `index 3` (各 PJ に散在) | 無害 (git は `.git/index` しか読まない) |
| その他 | `meishilink/.git/AUTO_MERGE 2`<br>`tomori/.git/logs/refs/remotes/origin/main 2` | 無害 |

**ref の複製がある repo では、git 操作が理不尽に失敗する**:

```
$ git checkout feature/version-management
fatal: bad object refs/remotes/origin/main 2

$ git fsck
error: refs/remotes/origin/main 2: badRefName: invalid refname format
error: refs/remotes/origin/main 2: invalid sha1 pointer 0000000000000000000000000000000000000000
```

**二次被害が厄介**: checkout が失敗するので、**worktree が feature ブランチから外れて detached HEAD に取り残される**。実際 `atender-version-management` worktree は `feature/version-management` (f4da366) にいるはずが `dd783ce` の detached HEAD にいた。`git worktree list` は数分前まで正しいブランチを表示していたので、**「いつの間にか変わっている」形で顕在化する**。

**最大の実害は誤診**: エージェントが git を叩くたびに理不尽に失敗するので、**「Claude CLI が壊れた / エージェントが暴走した」に見える**。実際 Touri は「バグり散らかしてた」としてセッションを落として再起動していた。原因は環境で、セッションは無実だった。

## Why

iCloud / Finder は同名衝突時にファイル名へ ` 2` を付けて複製する。git は `refs/` 配下を**ファイル名でそのまま ref 名として列挙する**ため、スペースを含む `main 2` を不正な refname として読み、ref 走査を伴う操作 (checkout / fsck / branch 表示など) ごと落とす。

`index` / `logs/` / `AUTO_MERGE` の複製が無害なのは、git がそれらを**固定パスで開く**だけで、ディレクトリを列挙しないから。**refs/ だけが「ディレクトリの中身 = ref の集合」という構造**を持つので、そこにゴミが入ると死ぬ。

## How to apply

**症状からの逆引き** — 以下を見たら真っ先に疑う:

- `fatal: bad object refs/...` / `badRefName`
- worktree が身に覚えなく detached HEAD 化している
- 特定 repo でだけ git が不安定 / エージェントの挙動がおかしい

**検出**:

```sh
find <repo>/.git \( -name "* 2" -o -name "* 3" -o -name "* 2.*" \) 2>/dev/null
git -C <repo> fsck --no-progress 2>&1 | grep -E "badRefName|invalid"
# ツリー全体を舐めるなら
find <root> -path "*/.git/*" \( -name "* 2" -o -name "* 3" \) 2>/dev/null
```

`git fsck` の `dangling commit` は**正常な残骸**なので無視してよい。拾うのは `error:` 行だけ。

**除去 — 種類で危険度が違う。一律 `rm` しない**:

| 対象 | 判断 |
|---|---|
| `refs/remotes/**` の複製 | **無条件に消してよい。** remote-tracking ref は `git fetch` で必ず再生成される捨て物 |
| `refs/heads/**` の複製 | **消す前に本物の確認が要る。** ローカルブランチなので、本物 (`main`) が健在で、複製が指す sha が到達可能かを `git cat-file -t <sha>` / `git log --oneline -1 <sha>` で見てから。孤立コミットを唯一指しているなら消す前に退避 |
| `index` / `logs/` / `AUTO_MERGE` の複製 | 無害。掃除してよい |

**除去後は必ず `git fsck` で `error:` が消えたことを確認**してから、detached HEAD になった worktree を `git checkout <branch>` で戻す。

**恒久策**: `icloud-synced-venv-git-stall.md` の恒久策 (repo を iCloud 同期対象外へ) と同じ。ただし**移動作業そのものが複製を生む**ので、**移動が終わった直後に一度ツリー全体を上記 find で掃除する**こと。移動して安心した後に発症するのがこの罠の性格。

関連: [[gotcha/icloud-synced-venv-git-stall]] (同じ根・evict による stall)
