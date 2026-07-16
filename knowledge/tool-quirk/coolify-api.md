---
title: Coolify API の癖と未公開仕様
category: tool-quirk
tags: [coolify, api, openapi, deploy]
created: 2026-05-10
updated: 2026-07-16
project: global
sources:
  - https://coolify.io/docs/api-reference
  - https://raw.githubusercontent.com/coollabsio/coolify/main/openapi.yaml  # spec の info.version は '0.1' 固定で semver なし。確認時の commit SHA を残すこと
  - https://github.com/coollabsio/coolify/releases/tag/v4.0.0  # 2026-04-27 release
  - https://github.com/coollabsio/coolify/blob/main/app/Jobs/ApplicationDeploymentJob.php  # 実装の真実。openapi で足りない時はここを読む (確認 SHA: 07f381b, 2026-07-16)
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

### ★ Dockerfile build pack の build context は `base_directory` そのもの

`ApplicationDeploymentJob.php` の実装 (2026-07-16 時点):

```php
$this->workdir = "{$this->basedir}".rtrim($baseDir, '/');   // basedir = clone先
// ...
"docker build -f {$this->workdir}{$this->dockerfile_location} -t {$image} {$this->workdir}"
```

つまり:

- **build context = `workdir` = clone root + `base_directory`**。context を独立に指定するフィールドは **存在しない** (OpenAPI にも実装にもない)
- **Dockerfile の実パス = `workdir` + `dockerfile_location`**。`dockerfile_location` が base_directory 相対なのはこの連結が理由
- `base_directory: "/"` は `rtrim("/", "/")` → `""` になるので **workdir = リポジトリ root** (バリデーションもスキップされる)

★ **モノレポで「context はリポジトリ root、Dockerfile は apps/web/Dockerfile」をやりたい場合の正解**:

```json
{"base_directory": "/", "dockerfile_location": "/apps/web/Dockerfile"}
```

→ `docker build -f <root>/apps/web/Dockerfile <root>` になる。
pnpm workspace のように root の lockfile / 他パッケージが context に要る構成はこれで成立する。
逆に `base_directory: "/apps/web"` にすると context が `apps/web` に閉じるので root の
`pnpm-lock.yaml` が COPY できない。**context を広げたい = base_directory を上げる** が唯一の操作。

deploy 時の clone は full clone (`--depth=1` はあり得る) で、`base_directory` による sparse-checkout は**しない**
(sparse-checkout は docker-compose ファイル読み取り用のヘルパー経路のみ)。→ base_directory を絞っても
リポジトリ全体は clone されているが、**context には入らない**。

### healthcheck の癖 (scratch / distroless で詰む)

Coolify は healthcheck を **コンテナ内で実行する compose healthcheck** として生成する:

```php
'test' => ['CMD-SHELL', "curl -s -X 'GET' -f 'http://localhost:<port>/<path>' > /dev/null || wget -q -O- '<url>' > /dev/null || exit 1"]
```

- ★ **`curl` か `wget` か、最低でも shell がコンテナ内に必要**。`scratch` / `distroless`(非 debug) は shell も両者も無いので **常に unhealthy → デプロイ失敗**
  - Coolify 自身も rust テンプレで `// temporary: disable healthcheck for rust because the start phase does not have curl/wget` と書いて逃げている (ApplicationDeploymentJob.php)
  - **alpine は busybox の `wget` を持つ** (`/usr/bin/wget`、`curl` は無い) ので `curl || wget` の後段が通る = そのまま動く (alpine 3.22.5 minirootfs で実測)
- `health_check_port` 未指定なら `ports_exposes` の**先頭**が使われる
- ★ **`health_check_type` / `health_check_command` は GET レスポンス (`Application` schema) にしか無く、POST 作成 body にも PATCH body にも無い** → **API から cmd 型 healthcheck は設定できない** (UI 専用機能と思われる)。API 運用なら選択肢は「HTTP healthcheck が通るイメージにする」か「healthcheck を切る」の二択
- Dockerfile 側 `HEALTHCHECK` を使わせたい場合の条件が非直感的:
  - `parseHealthcheckFromDockerfile()` が `custom_healthcheck_found = true` にするのは **`health_check_enabled = false` のとき** かつ HEALTHCHECK 行に `--interval` / `--timeout` / `--start-period` / `--retries` のいずれかがある場合のみ
  - `health_check_enabled = true` のままだと Coolify の curl/wget healthcheck が compose に書かれ、**イメージ側 HEALTHCHECK を上書きする**
  - つまり「Dockerfile の HEALTHCHECK に任せる」= **`health_check_enabled: false` + Dockerfile に flag 付き HEALTHCHECK** の組み合わせ

### デプロイ完了の待ち方 (API)

- `GET /deploy?uuid=<a>,<b>` は **uuid のカンマ区切りを受け付ける** (複数アプリを 1 回で deploy)。返りは `{"deployments":[{message, resource_uuid, deployment_uuid}]}`
- `deployment_uuid` を `GET /deployments/{uuid}` に投げて `status` をポーリングする。取り得る値は `App\Enums\ApplicationDeploymentStatus` の 5 つ:
  `queued` / `in_progress` / `finished` / `failed` / `cancelled-by-user`
  (OpenAPI 上は `status: {type: string}` で enum 記述が無い ★ spec 側の情報不足)

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

★ **`envs/bulk` は重複行を作ることがある**: 1 回の bulk 投入で各キーが 2 行できた (同 key が別 `uuid` で二重化)。原因未確定だが実害あり。投入後は必ず `GET /applications/{uuid}/envs` で重複を確認し、余分を `DELETE /applications/{uuid}/envs/{env_uuid}` で掃除する運用にする。

### resource 作成 (project / app / database) の癖

- **`POST /projects` の `description` は許可文字が限定**: letters / numbers / spaces と `- _ . , ! ? ( ) ' " + = * / @ &` のみ。**emダッシュ `—` や日本語の一部記号を含めると 422**。OpenAPI schema には pattern 記述がない (実装側のバリデーション)。ASCII 無難記号で書く。`name` は制約ゆるめ。
- **app / database 作成は `environment_uuid` が必須**: `POST /applications/private-github-app` `/public` `/private-deploy-key` `/dockerfile` `/dockerimage` および `POST /databases/*` の required に `environment_name` と `environment_uuid` **両方**が載っている。description は "at least one" と書くが、実踏では `environment_name` だけでは作成できず uuid が要る。environment uuid は `GET /projects/{uuid}` の `.environments[].uuid` からしか取れない (project 一覧には出ない)。
- **private repo の deploy key が org ポリシーで無効なことがある**: `POST /applications/private-deploy-key` が `Deploy keys are disabled` で 422 (例: `n-wasabi` org)。その場合は **GitHub App ソース経由** (`private-github-app`) に切り替える。

### GitHub App ソースの癖

- **`POST /github-apps` は API 登録可**だが必須項目 `installation_id` は **GitHub 側で App を org に install 済みでないと存在しない**。App の作成/install は GitHub のブラウザ manifest フローが必須で REST 不可。→ 現実は **Coolify UI の Sources → GitHub App フロー**が「App 作成 + org install + Coolify 登録」を束ねて最短。app 作成に渡す `github_app_uuid` は登録後 `GET /github-apps` の `.uuid`。
- **`GET /github-apps/{github_app_id}/repositories` (load-repositories) は path に数値 `id` を要求**。uuid を渡すと 500 (`SQLSTATE 22P02 invalid input syntax`)。`GET /github-apps` の `.id` (integer) を使う。同 endpoint は `.id` と `.uuid` の両方を返すので用途で使い分け (app 作成は uuid、repo/branch ロードは id)。
- `docker_compose_raw` (`POST /services`) と `custom_labels` (PATCH app) は **base64 encoded** で送る。生 string は reject。

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

### database の接続 URL は API で取れる (OpenAPI spec に無い)

`GET /databases` / `GET /databases/{uuid}` の実レスポンスには **`internal_db_url` / `external_db_url`** が含まれる (実測 2026-07-05)。OpenAPI yaml の schema にはこのフィールドが無い (★ spec 乖離、実装が正)。

- `internal_db_url` = `postgres://user:pass@<container-name>:5432/<db>` 形式。同一 server の app からは docker 内部 network 経由でこの URL をそのまま `DATABASE_URL` に env 注入すればよい (ポート公開不要)
- `is_public=true` + `public_port` を設定した時だけ `external_db_url` が外部接続可能になる (通常は不要・閉じておく)
- app と DB が別 destination network の場合は app 側 `connect_to_docker_network` (PATCH 可、OpenAPI にあり) で predefined network 接続を有効化する。standalone (StandaloneDocker) 同士・同一 server なら通常そのまま届く

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
