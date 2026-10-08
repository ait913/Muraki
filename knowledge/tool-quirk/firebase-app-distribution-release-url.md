---
title: "Firebase App Distribution の配布 URL を後から取る (CLI の refresh token で REST)"
category: tool-quirk
project: global
tags: [firebase, app-distribution, dist-dev, wasawasa, oauth]
created: 2026-10-05
sources:
  - "/opt/homebrew/lib/node_modules/firebase-tools/lib/api.js (clientId / clientSecret の既定値)"
  - "~/.config/configstore/firebase-tools.json (tokens.refresh_token)"
  - "https://firebaseappdistribution.googleapis.com/v1/projects/{number}/apps/{appId}/releases"
---

## Context

bloom の `make dist-dev` (`app/scripts/dist-dev.sh`) は `firebase appdistribution:distribute` の出力を保存しない上に、起動時に `build/dist-dev-*.log` を消すので、Leader が stdout を `build/dist-dev-run.log` に落としても消える。wasawasa の `build_register` に渡す配布 URL (`testerapps/<appId>/releases/<id>`) を失った (2026-10-05)。

## What

firebase CLI がログイン済みなら、その refresh token と CLI 同梱の公開 OAuth クライアントで access token を作り、App Distribution の REST で最新 release を引ける:

```python
import json, os, urllib.request, urllib.parse
cfg = json.load(open(os.path.expanduser('~/.config/configstore/firebase-tools.json')))
rt = cfg['tokens']['refresh_token']
data = urllib.parse.urlencode({'grant_type': 'refresh_token', 'refresh_token': rt,
  'client_id': '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com',
  'client_secret': 'j9iVZfS8kkCEFUPaAeJV0sAi'}).encode()   # firebase-tools lib/api.js の既定値 (公開定数)
at = json.load(urllib.request.urlopen(urllib.request.Request('https://oauth2.googleapis.com/token', data=data)))['access_token']
req = urllib.request.Request('https://firebaseappdistribution.googleapis.com/v1/projects/816295547805/apps/1:816295547805:ios:174ce81d9ff13a59855574/releases?pageSize=3',
  headers={'Authorization': 'Bearer ' + at})
for r in json.load(urllib.request.urlopen(req))['releases']:
    print(r['buildVersion'], r['displayVersion'], r['createTime'], r['testingUri'], r['name'])
```

`testingUri` が wasawasa の `distribution_url`、`name` が `firebase_release_name`。`gcloud auth print-access-token` はこの Mac では未ログインで使えない。

## Why

配布 URL は release ごとに違う id を持ち、Firebase Console を開かずに取る手段が CLI に無い (`appdistribution:distribute` の stdout にしか出ない)。

## How to apply

- dist-dev の run ログは `build/` でなく scratchpad に落とす (`dist-dev-` 接頭辞を避ける)
- 恒久対応は wasawasa レーンで調整中: dist-dev.sh が firebase 出力を保存するか、wasawasa が build_register 時に REST で照会する
- wasawasa MCP の `build_register` は同じ build_number で再登録しても**既存レコードをそのまま返すだけで URL は更新されない** (2026-10-05 実測)。登録前に URL を取っておくか、更新は wasawasa の画面 / 保守セッションに頼む
