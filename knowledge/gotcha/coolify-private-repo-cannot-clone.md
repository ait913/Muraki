---
title: Coolify は private GitHub repo を default で clone できない (Public Repo 用フロー)
category: gotcha
project: global
tags: [coolify, github, deploy, auth, private-repo]
created: 2026-05-26
sources:
  - https://coolify.io/docs/applications/github-app
  - 実体験: omatase-demo 初回 deploy 失敗 "fatal: could not read Username for 'https://github.com'"
---

## Context

Coolify (`coolify.aisaba.net`) で **Public Repo** build pack (`POST /applications/public`) を使ってアプリを作成し、`git_repository: "https://github.com/<owner>/<private-repo>"` で deploy 開始すると、build container 内で `git ls-remote` が **認証要求**を出して即 fail する:

```
fatal: could not read Username for 'https://github.com': No such device or address
Deployment failed: Command execution failed (exit code 128)
```

これは Coolify 側に GitHub の認証情報が無いため。`Public Repo` build pack は文字通り **public repo 限定**。

## What

私有 (private) repo を Coolify でデプロイするには 3 通り:

1. **Repo を public にする** (デモ・OSS なら最速。`gh repo edit <owner>/<repo> --visibility public --accept-visibility-change-consequences` 1 コマンド)
2. **GitHub App をインストール** (Coolify 推奨)。Coolify UI → Sources → Add GitHub App → owner/org にインストール → `POST /applications/private-github-app` で利用
3. **Deploy Key (SSH) を repo に登録** + `git_repository: git@github.com:...` 形式。`POST /applications/private-deploy-key`

Coolify UI で「Public Repository」を選んで作ると `applications/public` endpoint に行くため、**初手で private を選ばないと build 段階まで来てから失敗**する。事前に repo の public/private を意識して endpoint を選ぶこと。

## Why

`Public Repo` build pack は HTTPS unauthenticated `git ls-remote` を叩く。GitHub は private repo に対しては 401/Username prompt を返し、build container には `git credential helper` がないので即 fail。SKILL の手順例 (`POST /applications/public`) は **public repo 前提**だが、SKILL 内に明示されていない。

## How to apply

新規 Coolify アプリ作成時のチェックリスト:

```sh
# 0. repo の visibility を先に確認
gh repo view <owner>/<repo> --json visibility,isPrivate

# 1a. public ならそのまま POST /applications/public で OK
# 1b. private なら以下のいずれか:
#   - public 化 (デモ用途):
gh repo edit <owner>/<repo> --visibility public --accept-visibility-change-consequences
#   - GitHub App or Deploy Key:
#     Coolify UI から Sources を追加してから POST /applications/private-github-app
```

### 復旧 (既に build 失敗した場合)

repo を public 化したら、**force=false で十分** (Coolify は git fetch を再試行する、cache 関係ない):

```sh
curl -sS -H "Authorization: Bearer $COOLIFY_API_TOKEN" "$COOLIFY_API_BASE/deploy?uuid=<app-uuid>&force=false"
```

## 関連

- [`appily SKILL`](../../../.claude/skills/appily/SKILL.md) — Coolify 操作カタログ。本書の内容は SKILL 「新規アプリ作成標準フロー」の前段チェック項目として補完
- [`gotcha/coolify-traefik-stale-label-loop.md`](./coolify-traefik-stale-label-loop.md) — clone 成功後、別の罠 (self-redirect loop)
- [`tool-quirk/coolify-api.md`](../tool-quirk/coolify-api.md)
