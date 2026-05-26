---
title: cloudflared tunnel login は 1 zone しか cert.pem に入れない — 複数 zone は API token を使う
category: tool-quirk
tags: [cloudflared, cloudflare-tunnel, cert.pem, api-token, dns-route]
created: 2026-05-20
project: global
sources:
  - https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/
  - 実機検証 (cloudflared 2026.5.0, 2026-05-20)
---

## Context

`cloudflared tunnel login` で発行される `~/.cloudflared/cert.pem` (Origin CA cert + Argo Tunnel API service token) は、`cloudflared tunnel route dns <tunnel> <hostname>` で **どの zone に CNAME を作れるか** を決める。複数 zone (例: aisaba.net + appily.run + ceez7.com) を管理したい場合、cert.pem が**最後に認可した 1 zone 分しか持たない**ので、他 zone への操作が誤動作する。

## What

`cloudflared tunnel login` を実行 → ブラウザの Authorize 画面で複数 zone にチェックを入れた (ように見えた) → cert.pem サイズが 282 byte。

その状態で `cloudflared tunnel route dns -f aisaba-home '*.appily.run'` を実行すると、エラーにならず、**aisaba.net zone 内に `*.appily.run.aisaba.net` という奇妙な CNAME が作成される**。これは「権限を持つ zone (= aisaba.net) で名前を相対解釈した」結果。

```
2026-05-19T19:15:37Z INF Added CNAME *.ceez7.com.aisaba.net which will route to this tunnel
2026-05-19T19:15:39Z INF Added CNAME ceez7.com.aisaba.net which will route to this tunnel
2026-05-19T19:15:40Z INF Added CNAME *.appily.run.aisaba.net which will route to this tunnel
```

`cloudflared tunnel login` を `mv cert.pem cert.pem.old` してから再実行しても、cert.pem サイズは 282 byte のまま → cert.pem には**事実上 1 zone 分の権限しか格納できない** (UI で複数チェックしても無視される or 最後の 1 つだけ残る)。

## Why

Cloudflare の Argo Tunnel API service token は zone 単位で発行される。`cloudflared tunnel login` は内部的に 1 つの zone-scoped token を取得して cert.pem に書き込む処理 (推測)。複数 zone を一括で扱うには user-scoped API token が必要だが、login コマンドはこの方式に対応していない。

公式 docs にこの制限は明記されていない (2026-05 時点)。

## How to apply

**結論: 複数 zone を扱うときは `cloudflared tunnel login` ではなく Cloudflare API token を直接使う。**

### 推奨フロー

1. **Cloudflare dashboard** → https://dash.cloudflare.com/profile/api-tokens
2. **Create Token** → **Edit zone DNS** テンプレート
3. **Zone Resources** で Include を必要な zone 分追加 (例: aisaba.net / appily.run / ceez7.com)
4. **Create Token** → 表示された token を `Muraki/.tmp/cf-token.txt` (gitignored) に保管
5. token を使って curl で zone ID 取得 + DNS 操作:

```bash
TOKEN=$(cat Muraki/.tmp/cf-token.txt)

# 全 zone 列挙
curl -s "https://api.cloudflare.com/client/v4/zones?per_page=50" \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print('\n'.join(f'{z[\"name\"]:20} {z[\"id\"]}' for z in d.get('result',[])))"

# 既存 A 削除 (record id は DNS 一覧から取得)
curl -s -X DELETE \
  "https://api.cloudflare.com/client/v4/zones/<zone-id>/dns_records/<record-id>" \
  -H "Authorization: Bearer $TOKEN"

# wildcard CNAME 作成
curl -s -X POST \
  "https://api.cloudflare.com/client/v4/zones/<zone-id>/dns_records" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"type":"CNAME","name":"*.appily.run","content":"<tunnel-uuid>.cfargotunnel.com","proxied":true}'
```

### `cloudflared tunnel login` を使っていい場合

- **管理する zone が 1 個だけ** の場合
- もしくは **Tunnel 作成時の cert.pem 取得のみ** (route dns は後で API で実行する) と割り切る場合

### 既に誤作成された変な CNAME の掃除

aisaba.net zone 内に `*.appily.run.aisaba.net` のような変な CNAME ができてしまったら、CF dashboard / API で DELETE。Tunnel に向いているが該当ホスト名は誰も使わないので放置でも害はないが、`*.aisaba.net` wildcard の判定で曖昧さが残るので削除推奨。

## 関連

- `[[cloudflare-tunnel-2026]]` — Tunnel 全体構成
