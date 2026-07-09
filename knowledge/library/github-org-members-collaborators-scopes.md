---
title: GitHub org members / collaborators API と classic OAuth scope (repo vs read:org) 2026
category: library
project: global
tags: [github, oauth, scope, read-org, org-members, collaborators, dandan]
created: 2026-07-07
sources:
  - https://docs.github.com/en/rest/orgs/members
  - https://docs.github.com/en/rest/collaborators/collaborators
  - https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps
  - https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps
  - https://docs.github.com/en/organizations/managing-oauth-access-to-your-organizations-data/about-oauth-app-access-restrictions
---

## Context

dandan-app (OAuth App classic, scope=`repo`) で org メンバーを名簿候補に拾う設計の事前調査 (2026-07-07)。

## What

- **`GET /orgs/{org}/members`**: 「authenticated user が org member なら concealed+public 両方、そうでなければ public のみ」(公式 docs 明記)。public members は**無認証でも 200** (実プローブ確認)。認証済みプローブで `X-Accepted-OAuth-Scopes` は空 = endpoint 自体の hard scope gate なし。concealed member を classic token で見るのに `read:org` が要るかは docs のページ抽出では明文確認できず (scopes doc の `read:org` = "Read-only access to organization membership, organization projects, and team membership" が根拠)。
- **`GET /repos/{owner}/{repo}/collaborators`**: `affiliation` default は `all`。org-owned repo では「outside collaborators / direct collaborator の org member / team 経由 / org default (base) permission 経由 / org owners」全部入り。ただし (1) **requester は repo に push (write/maintain/admin) 権限必須** — 実プローブで 403 "Must have push access to view repository collaborators." を確認、(2) 公式 docs は classic token に **`read:org` と `repo` の両 scope** を要求と明記 (= scope=`repo` のみの現行 dandan は org-owned repo でドキュメント上不足)。
- **owner が org か個人かの判定**: `GET /repos/{owner}/{repo}` の `owner.type` が `"User"` / `"Organization"` (実プローブ確認)。追加 API 不要。
- **scope 追加の再認可**: authorize URL の scope に `read:org` を足すと、既認可ユーザーにも consent 画面が再表示される (「requested scopes を既に認可済みの場合のみスキップ」の裏返し)。新トークンは新 scope set を持つ。**既発行トークンは無効化されない** (10-token 上限は user/app/scope組合せ単位)。stateless 構成 (トークンを MCP token に封入) では既存セッションは旧 scope のまま生き続ける → graceful degrade か再ログイン誘導が要る。
- **OAuth App access restrictions**: **新規 org はデフォルト有効**。未承認 OAuth App は「API access to private organization resources is not available」= scope に関係なく private org データ (concealed members 含む) 不可。authorize 画面で org ごとに Grant / Request approval。org owner の承認で解除。

## Why

`repo` scope は「repo とその org-owned リソースの管理」であって org membership の read を明文で含まない。org 名簿系は `read:org` が正規 scope。加えて org 側の App 承認という第二のゲートがあり、scope を足しても restricted org では承認まで private データは見えない。

## How to apply

- org メンバー名簿を拾うなら scope を `repo read:org` に (collaborators endpoint の docs 要件も同時に満たす)。
- owner.type=Organization のときだけ `/orgs/{org}/members` を叩き、User なら collaborators のみにフォールバック。
- 403/空応答は「org 未承認 or 旧 scope トークン」の両方があり得る。`X-OAuth-Scopes` response header で token の実 scope を判別できる。
- GitHub App 移行は不要 (OAuth App のままで成立)。制約は「ユーザー自身が org member であること」「restricted org は owner 承認」の 2 点。
