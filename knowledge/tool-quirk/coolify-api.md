---
title: Coolify API の癖と未公開仕様
category: tool-quirk
tags: [coolify, api, openapi, deploy]
created: 2026-05-10
updated: 2026-05-12
project: global
sources:
  - https://coolify.io/docs/api-reference
  - https://raw.githubusercontent.com/coollabsio/coolify/main/openapi.yaml  # spec の info.version は '0.1' 固定で semver なし。確認時の commit SHA を残すこと
  - https://github.com/coollabsio/coolify/releases/tag/v4.0.0  # 2026-04-27 release
---

> **不明点が出たら必ず公式を見る**: OpenAPI yaml と docs を一次情報として扱う。本ファイルは実踏知見の記録であり、最新仕様は公式と乖離している可能性がある。
> - OpenAPI: <https://raw.githubusercontent.com/coollabsio/coolify/main/openapi.yaml>
> - Docs: <https://coolify.io/docs/api-reference>

## Context

Coolify (オンプレ Ubuntu サーバ `coolify.aisaba.net`) を HTTP API 経由で操作する際、公式 OpenAPI と実装の食い違い・公式 docs に書いてない癖が多数ある。MeishiLink デプロイで詰まって発見した知見。

## What

### PATCH `/applications/{uuid}` の癖

| field | 仕様 | 注意 |
|---|---|---|
| `custom_labels` | string、改行区切りの Traefik label list | **Coolify 実装は base64-encoded を要求**。生 string で送ると `"The custom_labels should be base64 encoded."` エラー。GET レスポンスでは `null` 表示 (write only) |
| `is_force_https_enabled` | boolean、**default true** (公式 docs より) | GET レスポンスに含まれない (write only)。Cloudflare 経由でループの原因になりがち |
| `redirect` | enum: `www` / `non-www` / `both` のみ | `"none"` 文字列は invalid。spec では `nullable: true` だが実装が `null` を accept するかは未確認 — 実踏では `null` も reject されたが OpenAPI commit によって挙動変わる可能性あり |
| `domains` | string (空にすると fqdn null 化) | `fqdn` field は read-only、書き込みは `domains` 経由 |
| `generate_exact_labels` | アプリ単位で **patch 不可** | server / destination レベルの設定。OpenAPI スキーマに無い |
| `git_repository` | **PATCHでは `owner/repo`、POSTでは完全URL** | ★ format がメソッドで違う罠。`POST /applications/public` 作成時は `https://github.com/owner/repo` (完全URL必須、`owner/repo` 形式は `must start with https://...` エラー)。**作成後の保存値は `owner/repo` に変換される**。PATCHで完全URL指定すると、Coolify内部で `https://github.com/` を再prefix → `https://github.com/https://github.com/...` になり `Not Found`。**PATCHは必ず `owner/repo` 形式で送る** |
| `source_id` / `source_type` | PATCH **不可** | 作成時のみ指定可。後から変更したいなら delete + 再作成 |
| `dockerfile_location` | **`base_directory` からの相対 path** (絶対 path セマンティクス) | ★ `/Dockerfile` のように `/` 始まりだが、これは「リポジトリroot」ではなく「base_directory の中」。`base_directory: "/mobile"` で `dockerfile_location: "/mobile/Dockerfile.web"` を指定すると `/artifacts/.../mobile/mobile/Dockerfile.web` と二重 prefix になり `lstat ... no such file`。正しくは `dockerfile_location: "/Dockerfile.web"` |

### env 登録 API の癖

`POST /applications/{uuid}/envs` の body は `{key, value, is_preview, is_literal, is_multiline, is_shown_once}` (OpenAPI `EnvironmentVariable` schema):

- **production と preview の両方に同じ env が作られる** (preview を使わなくても 2 entry 出る、無害)
- `is_build_time` (`is_buildtime`) field は **POST/PATCH body では送るとエラー** (`"This field is not allowed."`) だが、★ **GET レスポンスの `EnvironmentVariable` schema には `is_buildtime` が含まれる** (write 不可・read 可の非対称性)
- `NODE_ENV=production` を登録すると **builder stage の `npm ci` まで影響**して devDependencies がスキップされ、Next.js の TypeScript 自動 install が peer 競合で失敗する → Coolify env では NODE_ENV を**設定しない**。Dockerfile の runner stage で `ENV NODE_ENV=production` を書く

### env bulk endpoint (見落としがち)

`PATCH /applications/{uuid}/envs/bulk` で env を一括更新できる。新規アプリ作成直後の env 一括登録に有用 (1 件ずつ POST より速く、production/preview 両建ても集約)。

```sh
curl -sS -X PATCH -H "Authorization: Bearer $COOLIFY_API_TOKEN" \
  -H "Content-Type: application/json" \
  "$COOLIFY_API_BASE/applications/<uuid>/envs/bulk" \
  -d '{"data":[{"key":"...","value":"...","is_preview":false}, ...]}'
```

### ログ取得の癖

- `GET /applications/{uuid}/logs?lines=N` は **コンテナが running 状態のときしか返らない**。クラッシュループ中は `{"message":"Application is not running."}` を返す
- 起動エラーをキャッチするには **再起動の隙間 0.x 秒で race-catch** するしかない:
  ```sh
  curl ... /applications/<uuid>/restart
  for i in $(seq 1 30); do
    resp=$(curl ... /applications/<uuid>/logs?lines=200)
    echo "$resp" | grep -q '"logs"' && { echo "$resp" | <parse>; break; }
    sleep 1
  done
  ```
- レスポンスは JSON だが logs フィールド内に control character を含むと jq でパースできない → Python で `bytes(s,'utf-8').decode('unicode_escape')` 経由で抽出
- ANSI カラーコードは `sed -r 's/\x1b\[[0-9;]*[mK]//g'` でストリップ

### deployment ログの癖

- `GET /deployments/{uuid}` は **OpenAPI 上は `ApplicationDeploymentQueue` schema (logs フィールドを含む) を返す** はずだが、実踏では status のみで logs 空のことが多い (★ spec と impl の乖離。spec のほうが「正解」のはずで、空なのはバグか version 差)
- 過去 deployment のフルログは `GET /deployments/applications/{uuid}` の各エントリの `logs` フィールド (二重 JSON encoded、parse 二段階)。spec 上は `Application` 配列が return type だが、実挙動は `ApplicationDeploymentQueue` 配列 (★ spec のバグ疑い)
- どちらが入るか不安定なので、**両方叩いて logs が長い方を採用**する防御策が安全

### domain conflict (409)

`PATCH /applications/{uuid}` および `POST /applications/public` で `domains` を指定したとき、**他アプリと衝突すると 409 Conflict** が返る (response body に競合先 app 情報)。

回避: query string `force_domain_override=true` を付けると競合を強制上書き。**他アプリの fqdn を奪う破壊操作**なのでユーザー承認必須。

```sh
curl -X PATCH ... "$COOLIFY_API_BASE/applications/<uuid>?force_domain_override=true" -d '{"domains":"https://..."}'
```

### 存在しない endpoint

- proxy restart API はない (UI からのみ)
- container 内 docker exec API もない
- Traefik 生成 label の確認 API もない

→ これらが必要な場面では SSH に落ちる必要がある (Coolify 管理画面右上 → Servers → 該当 server → Proxy → Restart ボタンを叩いてもらう手も)

## Why

Coolify は Laravel + Livewire 製で、UI 機能が API より先行する傾向。OpenAPI ドキュメントと実装で乖離があるのは「UI 機能が後追いで API 化されてない」だけで、ソースを `bootstrap/helpers/docker.php` 等で読むと挙動が分かる。

`custom_labels` の base64 強制はおそらく改行入り文字列を URL/JSON で安全に運ぶための歴史的経緯。Docs にこの注意書きが無い。

`is_force_https_enabled` write-only は単に `select` 句から漏れてる Laravel 実装の漏れと思われる。

## How to apply

別プロジェクトで Coolify をデプロイ先に選ぶ場合:

1. **環境変数登録は必ず本番起動前に** (空 env でデプロイすると next-auth 等が起動時 throw → クラッシュループ)
2. **NODE_ENV を Coolify env に登録しない**。Dockerfile runner stage でハードコード
3. **デバッグ時は logs API を race-catch**。Bash one-liner を sometimes-race スクリプトとして書ける状態にしておく
4. **`is_force_https_enabled` を最初から false に**。Cloudflare 経由なら Cloudflare 側で HTTPS 強制した方が安全
5. SSH 経路を確保しておく (port 51000 が open かつ source IP allow されてること)。Coolify API では届かない領域で必須
6. ナレッジに `gotcha/coolify-traefik-stale-label-loop.md` も合わせて参照
