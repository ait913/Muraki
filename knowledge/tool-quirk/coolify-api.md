---
title: Coolify API の癖と未公開仕様
category: tool-quirk
tags: [coolify, api, openapi, deploy]
created: 2026-05-10
updated: 2026-08-21
project: global
sources:
  - https://coolify.io/docs/api-reference
  - https://raw.githubusercontent.com/coollabsio/coolify/main/openapi.yaml  # spec の info.version は '0.1' 固定で semver なし。確認時の commit SHA を残すこと
  - https://github.com/coollabsio/coolify/releases/tag/v4.0.0  # 2026-04-27 release
  - https://github.com/coollabsio/coolify/blob/main/app/Jobs/ApplicationDeploymentJob.php  # 実装の真実。openapi で足りない時はここを読む (確認 SHA: 07f381b, 2026-07-16)
model-era: opus-4.8
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
  - **素の alpine は busybox の `wget` だけを持つ** (`/usr/bin/wget`、`curl` は無い) ので `curl || wget` の**後段**で通る (alpine 3.22.5 minirootfs で実測)。
    ★ ただし**「wget があるから通る」ではない** — busybox wget は `localhost` を `::1` で引いて **fallback しない**ので、
    コンテナが **IPv4-only bind** だと `Connection refused` で落ちる (omatase で実際にデプロイが落ちた)。
    後段が通る条件は「コンテナが dual-stack で bind している」こと。詳細: [`gotcha/coolify-healthcheck-localhost-ipv6-vs-node-bind.md`](../gotcha/coolify-healthcheck-localhost-ipv6-vs-node-bind.md)
  - ★ **`nginx:alpine` は実 curl (8.21.0、busybox でない) を同梱する**ので、IPv4-only bind でも**前段の curl** で通る (2026-07-16 実測)。
    「alpine 系だから wget 経路」と一括りにしないこと。詳細: [`library/coolify-static-buildpack.md`](../library/coolify-static-buildpack.md)
- `health_check_port` 未指定なら `ports_exposes` の**先頭**が使われる
- ★ **`health_check_type` / `health_check_command` は API から設定できる** (訂正 2026-07-16、Coolify **4.1.2** = 稼働中 `coolify.aisaba.net` の実バージョンのソースで確認、clone SHA `e7dff30`)。
  以前ここには「GET にしか無く POST/PATCH body には無い → cmd 型は API から設定できない」と書いてあったが**誤り**。
  根拠が `openapi.yaml` だけだったのが原因 — spec には GET の `Application` schema にしか出て来ないが、**実装は受け付ける**:
  - `ApplicationsController` の `$allowedFields` に **POST・PATCH 双方**で `health_check_type` / `health_check_command` が入っている
  - `sharedDataApplications()` (`bootstrap/helpers/api.php`) にバリデーションがある: `'health_check_type' => 'string|in:http,cmd'`、`'health_check_command' => ['nullable','string','max:1000','regex:/^[a-zA-Z0-9 \-_.\/:=@,+]+$/']`
  - `Application` model の `$fillable` に両方あり、`$application->fill($request->only($allowedFields))` で永続化される
  - カラムは migration `2025_12_25_072315_add_cmd_healthcheck_to_applications_table.php` で追加 (`health_check_type` default `'http'`)。**比較的新しい機能**なので古い Coolify では無い可能性がある — 使う前に `GET /applications` で `health_check_type` が返るか確認する
  - **本ファイルの他の「spec に無い」系の記述も openapi.yaml 由来なら実装を読み直すこと** (spec 乖離はこのリポジトリの常態)
- Dockerfile 側 `HEALTHCHECK` を使わせたい場合の条件が非直感的:
  - `parseHealthcheckFromDockerfile()` が `custom_healthcheck_found = true` にするのは **`health_check_enabled = false` のとき** かつ HEALTHCHECK 行に `--interval` / `--timeout` / `--start-period` / `--retries` のいずれかがある場合のみ
  - `health_check_enabled = true` のままだと Coolify の curl/wget healthcheck が compose に書かれ、**イメージ側 HEALTHCHECK を上書きする**
  - つまり「Dockerfile の HEALTHCHECK に任せる」= **`health_check_enabled: false` + Dockerfile に flag 付き HEALTHCHECK** の組み合わせ

### デプロイ完了の待ち方 (API)

- `GET /deploy?uuid=<a>,<b>` は **uuid のカンマ区切りを受け付ける** (複数アプリを 1 回で deploy)。返りは `{"deployments":[{message, resource_uuid, deployment_uuid}]}`
- `deployment_uuid` を `GET /deployments/{uuid}` に投げて `status` をポーリングする。取り得る値は `App\Enums\ApplicationDeploymentStatus` の 5 つ:
  `queued` / `in_progress` / `finished` / `failed` / `cancelled-by-user`
  (OpenAPI 上は `status: {type: string}` で enum 記述が無い ★ spec 側の情報不足)
- ★ **v4.3.9 (2026-08-21 確認) では `GET /deploy` と `GET /databases/{uuid}/{start,stop,restart}` が `{"message":"This endpoint has changed to a POST request."}` を返して弾く**。本ファイルや SKILL の「GET で叩く」という記述はこのバージョンでは通らない — **同じ query string のまま `-X POST` に変えるだけで通る** (body 不要)。`applications/{uuid}/{start,stop,restart}` は元々 POST 済みで影響なし。エラーメッセージがそのまま解決策なので、見たら method を疑わず即 POST に変える

### env が build-time ARG に混入して Dockerfile を壊す (改行を含む値は特に危険)

★ **`POST`/`PATCH .../envs[/bulk]` で `is_buildtime` を省略すると default `true`** (2026-08-21 実測)。Coolify はビルド時に**登録した全 env を `ARG key=value` として Dockerfile 先頭に注入**する (`docker build --build-arg`)。改行を含む値 (PEM 秘密鍵など) を `is_buildtime:true` のまま渡すと、生成される `ARG SIWA_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----\n<base64...>` の 2 行目以降が Dockerfile の**命令行として解釈**され `dockerfile parse error: unknown instruction: <base64の断片>` でビルド即死する。しかも**エラー出力に注入された ARG 一覧 (secret 含む) が平文で残る** (deployment log 経由で `GET /deployments/{uuid}` から取得可能)。

対処: ランタイムだけで使う env (DB URL, JWT_SECRET, PEM 鍵等) は **必ず `is_buildtime:false, is_runtime:true` を明示**して登録する。複数行値は `is_multiline:true` も付ける。事故った場合は該当 env を作り直すだけでなく、**漏れた値 (JWT_SECRET 等) をローテーションする** — 平文が deployment log に残ってしまうため。

```sh
curl -sS -X PATCH -H "Authorization: Bearer $COOLIFY_API_TOKEN" -H "Content-Type: application/json" \
  "$COOLIFY_API_BASE/applications/<uuid>/envs/bulk" \
  -d '{"data":[{"key":"JWT_SECRET","value":"...","is_preview":false,"is_buildtime":false,"is_runtime":true}]}'
```

### env 登録 API の癖

`POST /applications/{uuid}/envs` の body は `{key, value, is_preview, is_literal, is_multiline, is_shown_once}` (OpenAPI `EnvironmentVariable` schema):

- **production と preview の両方に同じ env が作られる** (preview を使わなくても 2 entry 出る、無害)
- ★ **`is_buildtime` は単発 `POST /applications/{uuid}/envs` の body で受け付けられる** (2026-07-30 実測 / omatase-web に `NEXT_PUBLIC_SUPABASE_URL` を `{"key","value","is_buildtime":true,"is_runtime":true}` で投入 → GET が `is_buildtime=true` を返した)。以前ここには「POST/PATCH body で送るとエラー (`This field is not allowed.`)」と書いてあったが**現行 Coolify では通る**。`is_build_time` (アンダースコア入り) の綴りは使わない
- `NODE_ENV=production` を登録すると **builder stage の `npm ci` まで影響**して devDependencies がスキップされ、Next.js の TypeScript 自動 install が peer 競合で失敗する → Coolify env では NODE_ENV を**設定しない**。Dockerfile の runner stage で `ENV NODE_ENV=production` を書く

### env bulk endpoint (見落としがち)

`PATCH /applications/{uuid}/envs/bulk` で env を一括更新できる。新規アプリ作成直後の env 一括登録に有用 (1 件ずつ POST より速く、production/preview 両建ても集約)。

```sh
curl -sS -X PATCH -H "Authorization: Bearer $COOLIFY_API_TOKEN" \
  -H "Content-Type: application/json" \
  "$COOLIFY_API_BASE/applications/<uuid>/envs/bulk" \
  -d '{"data":[{"key":"...","value":"...","is_preview":false}, ...]}'
```

★ **env の投入は経路に関係なく重複行を作ることがある**: `envs/bulk` の 1 回投入で各キーが 2 行できた事例に加え、**単発 `POST /applications/{uuid}/envs` でも 1 回の POST で 2 行できた** (2026-07-30 / omatase-web、2 キーとも二重化 = 2/2)。以前ここには bulk 固有の癖として書いてあったが**単発 POST でも起きる**。原因未確定 (production/preview の両建てとは別現象 — 両方 `is_preview=false` で重複した)。

→ **投入直後に必ず `GET /applications/{uuid}/envs` で件数と key を数え、余分を `DELETE /applications/{uuid}/envs/{env_uuid}` で掃除する**。重複を残すとどちらの値がビルドに渡るか不定になる。

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

### SOURCE_COMMIT はランタイムに自動注入される (ビルド時は設定が要る)

デプロイ中の git commit SHA は `SOURCE_COMMIT` env として **コンテナのランタイムに default で入る**。アプリが「自分がどの commit か」を名乗るのに Dockerfile 改造も build arg も不要 (`process.env.SOURCE_COMMIT` を読むだけ)。

`ApplicationDeploymentJob.php::generate_coolify_env_variables()` の実装 (**v4.1.2 タグで確認 = 本番稼働版と一致**, 2026-07-17):

```php
// Only add SOURCE_COMMIT for runtime OR when explicitly enabled for build-time
// SOURCE_COMMIT changes with each commit and breaks Docker cache if included in build
if (! $forBuildTime || $this->application->settings->include_source_commit_in_build) {
    if ($this->application->environment_variables->where('key', 'SOURCE_COMMIT')->isEmpty()) {
        $coolify_envs->put('SOURCE_COMMIT', $this->commit);   // 取れない時は 'unknown'
    }
}
```

| 文脈 | 入るか | 条件 |
|---|---|---|
| **ランタイム** (`$forBuildTime = false`) | **入る (default)** | ユーザーが同名 env を自分で定義していないこと |
| **ビルド時** (build arg / `/run/secrets/SOURCE_COMMIT`) | 入らない | app setting `include_source_commit_in_build` を有効化して初めて入る |

- PR preview 経路 (`pull_request_id !== 0`) も通常デプロイ経路も**同じ条件**
- ビルド時が default off なのは実装コメントのとおり **commit ごとに値が変わって Docker layer cache を壊すから**。フロント SPA に版数を焼き込みたい等でどうしても要るなら設定を入れるが、毎回フルビルドになるコストを承知で
- `GET /applications/{uuid}` の `git_commit_sha` は「デプロイ設定」であって実行中の SHA ではない (`HEAD` 等が入る)。**実際に動いている commit を知りたいならアプリ自身に `SOURCE_COMMIT` を喋らせる**のが確実

### 存在しない endpoint

- proxy restart API はない (UI からのみ)
- 専用の「container 内で任意コマンドを叩く」API はない
- Traefik 生成 label の確認 API もない

→ これらが必要な場面では SSH に落ちる必要がある (Coolify 管理画面右上 → Servers → 該当 server → Proxy → Restart ボタンを叩いてもらう手も)。ただし SSH (`ssh aisaba`) は Cloudflare Access の one-time PIN を**ブラウザで**踏む必要があり、エージェント単体では完結しない。

### ★ SSH なしでコンテナ内コマンドを実行する裏技 (scheduled-tasks execute)

`POST /applications/{uuid}/scheduled-tasks` (`frequency` は cron 必須だが `enabled:false` で自動発火は止められる) で任意コマンドのタスクを作り、`POST /applications/{uuid}/scheduled-tasks/{task_uuid}/execute` で**即時 1 回実行**できる。結果は `GET .../executions` の `message` フィールドに stdout がそのまま入る (`status: success/failed`, `duration`)。

- コマンドは `sh -c` 相当で実行される (alpine のように bash が無い distro でも busybox `sh` があれば通る)
- **`&&` を含む複合コマンドは Bash の `&&` 禁止フックとは無関係**だが、JSON body に埋め込むときは `;` で連結する方が失敗系の分岐を書きやすい (`touch x; echo exit=$?` のように exit code を明示的に拾う)
- 検証が終わったら `DELETE /applications/{uuid}/scheduled-tasks/{task_uuid}` で片付ける (残すと cron 式次第で意図せず定期実行される)
- 用途: **volume mount 後のパーミッション確認**、環境変数が実際にコンテナに届いているかの確認 (`env` コマンド)、ファイルの存在確認など、従来 SSH + `docker exec` が要ると思っていた作業の大半をカバーできる

```sh
curl -sS -X POST -H "Authorization: Bearer $COOLIFY_API_TOKEN" -H "Content-Type: application/json" \
  "$COOLIFY_API_BASE/applications/<uuid>/scheduled-tasks" \
  -d '{"name":"perm-check","command":"id; ls -ld /data; touch /data/.t; echo exit=$?; rm -f /data/.t","frequency":"0 0 1 1 *","enabled":false}'
# → uuid を取得して execute
curl -sS -X POST -H "Authorization: Bearer $COOLIFY_API_TOKEN" \
  "$COOLIFY_API_BASE/applications/<uuid>/scheduled-tasks/<task_uuid>/execute"
sleep 5
curl -sS -H "Authorization: Bearer $COOLIFY_API_TOKEN" \
  "$COOLIFY_API_BASE/applications/<uuid>/scheduled-tasks/<task_uuid>/executions" | jq -r '.[0].message'
# 検証後
curl -sS -X DELETE -H "Authorization: Bearer $COOLIFY_API_TOKEN" \
  "$COOLIFY_API_BASE/applications/<uuid>/scheduled-tasks/<task_uuid>"
```

### persistent storage (named volume) の初回マウント時、Dockerfile の chown は引き継がれる

Dockerfile で `RUN mkdir -p /data && chown -R app:app /data` した後に `USER app` → `ENTRYPOINT` という構成のイメージに、Coolify の `POST /applications/{uuid}/storages` (`type:persistent, mount_path:/data`) で**空の named volume を新規マウント**すると、**Docker の「copy-up」機構がイメージ側 `/data` の内容・所有権をそのまま volume にコピーする**ため、non-root ユーザーでも追加の対応なしに書き込める (2026-08-21, bloom-api で `touch` 成功を scheduled-tasks execute で実測: `drwxr-xr-x app app /data`)。

- ★ 「volume マウントで chown が上書きされて non-root が書けなくなる」という一般的な docker の罠は、**named volume が空 (=初回マウント) の場合は発生しない**。上書きが起きるのは host bind mount や、volume に既存データがあって copy-up がスキップされるケースなど別条件
- 何もしなくても通る場合が多いが、**「たぶん大丈夫」で終わらせず、上記 scheduled-tasks execute で `id` + `touch` を必ず実測する** (SSH 不要)
- もし実際に権限エラーが出たら、対処は (a) Dockerfile の `ENTRYPOINT` を `sh -c "chown -R app:app /data && exec /bin/api"` に変える (root で起動して chown 後に降格) か、(b) Coolify 側 custom_docker_run_options で `--user` を調整、のいずれか。今回は不要だった

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
