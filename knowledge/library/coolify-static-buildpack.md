---
title: Coolify の static build pack はビルドしない (リポジトリをそのまま nginx で配る)
category: library
tags: [coolify, static, nginx, buildpack, healthcheck, deploy]
created: 2026-07-16
project: global
sources:
  - https://github.com/coollabsio/coolify/blob/main/app/Jobs/ApplicationDeploymentJob.php  # build_static_image() / deploy_static_buildpack() (確認 SHA: e7dff30, 2026-07-16)
  - https://github.com/coollabsio/coolify/blob/main/bootstrap/helpers/shared.php  # defaultNginxConfiguration()
  - https://github.com/coollabsio/coolify/blob/main/bootstrap/helpers/api.php  # sharedDataApplications()
  - https://github.com/coollabsio/coolify/blob/main/app/Enums/StaticImageTypes.php
---

## Context

`build_pack` enum に `static` があるが、公式 docs は「静的サイト用」としか言わない。
「Astro/Vite のようにビルドが要る静的サイトに使えるのか」「ビルド済 HTML を置くだけなのか」が
docs からは読めない。n-wasabi HP (素の HTML/CSS) の設計前調査で実装を読んで確定させた。

**確認対象 = 稼働中の `coolify.aisaba.net` の実バージョン `4.1.2`** と、
同バージョンのソース (clone SHA `e7dff30`, `config/constants.php` = 4.1.2)。**版が一致している**。

## What

### ★ `build_pack: "static"` はビルドコマンドを一切実行しない

`deploy_static_buildpack()` → `build_static_image()` が生成する Dockerfile は**これが全て**:

```dockerfile
FROM nginx:alpine                      # ← static_image (enum は nginx:alpine のみ)
WORKDIR /usr/share/nginx/html/
LABEL coolify.deploymentId=<uuid>
COPY . .                               # ← workdir を丸ごと。ビルドは無い
RUN rm -f /usr/share/nginx/html/nginx.conf
RUN rm -f /usr/share/nginx/html/Dockerfile
RUN rm -f /usr/share/nginx/html/docker-compose.yaml
RUN rm -f /usr/share/nginx/html/.env
COPY ./nginx.conf /etc/nginx/conf.d/default.conf
```

- `npm install` も `build_command` も**呼ばれない**。`clone_repository()` → `cleanup_git()` → `COPY . .` だけ
- したがって **`static` は「リポジトリにコミット済のファイルをそのまま配る」用途**。
  素の HTML/CSS は**ど真ん中**。ビルドが要るもの (Astro/Vite) は `dist/` をコミットしない限り使えない
- ★ **`publish_directory` は `build_static_image()` から参照されない = 完全に無視される**。
  `publish_directory` が効くのは **`build_pack: nixpacks|railpack` + `settings.is_static: true`** の別経路
  (`build_railpack_static_image()` / nixpacks 経路が `COPY --from=<build image> /app<publish_dir> .` を書く)
- 配信範囲を絞る唯一の手段は **`base_directory`**。build context (= `workdir`) は
  `clone先 + base_directory` なので、`base_directory: "/site"` にすると `site/` の中身だけが配られる (実測)

### ★ `COPY . .` はリポジトリ全体を公開配信する

`base_directory: "/"` だと **README.md も `.github/workflows/*.yml` も HTTP で 200 で返る** (実測)。
除去されるのは `nginx.conf` / `Dockerfile` / `docker-compose.yaml` / `.env` の 4 つと、
`cleanup_git()` が消す `.git` **だけ**。private リポジトリでも**配信内容は公開**になる。

→ 配りたいものだけを置いたディレクトリを作り、**`base_directory` でそこを指す**のが対策 (実測で README が 404 になる)。

### ★ healthcheck は通る。ただし「curl があるから」通っている

- `static` / `is_static` のとき **Coolify は `health_check_port` を無条件で `80` に上書きする**
  (`if ($this->application->settings->is_static || $this->application->build_pack === 'static') { $health_check_port = 80; }`)。
  `ports_exposes` も `80` にする (POST 時に `$request->offsetSet('ports_exposes', '80')`)
- `nginx:alpine` は **IPv4 のみ bind** (`netstat` → `0.0.0.0:80`。tcp6 listener 無し) — omatase の Node/`HOSTNAME=0.0.0.0` と**同じ条件**
- `nginx:alpine` の実機プローブ (2026-07-16):

  | コマンド | 結果 |
  |---|---|
  | `curl -s -X 'GET' -f 'http://localhost:80/'` | **exit 0** (curl 8.21.0、busybox でない実 curl) |
  | `wget -q -O- 'http://localhost:80/'` | **exit 1** `can't connect to remote host: Connection refused` (busybox wget、`::1` を引いて fallback しない) |
  | `wget -q -O- 'http://127.0.0.1:80/'` | exit 0 |

- Coolify の生成コマンドは `curl ... || wget ... || exit 1` なので、**第 1 分岐の curl が成功して exit 0**。
  ★ **成立しているのは「nginx:alpine が実 curl を同梱しているから」の一点**。omatase の alpine (curl 無し・busybox wget のみ) は
  同じ `localhost` + IPv4-only bind で**落ちた**。条件は同じで、curl の有無だけが生死を分けている

### healthcheck の host は URL に逐語で埋まる (omatase の「不確定」を解消)

```php
$host = $this->sanitizeHealthCheckValue($this->application->health_check_host, '/^[a-zA-Z0-9.\-_]+$/', 'localhost');
$url  = escapeshellarg("{$scheme}://{$host}:{$health_check_port}".($path ?? '/'));
```

**正規化はされず、regex を通れば `health_check_host` の値がそのまま URL に入る** (通らなければ `localhost` に fallback)。
`127.0.0.1` は regex を通るので逐語で入る。
→ omatase 設計doc の「Coolify が host をどう埋めるか未検証」は**解消**。ただし omatase の A 案
(コンテナ側 dual-stack) は「Coolify 側の挙動に依存しない」という理由で選んでおり、その判断自体は今も有効。

### `redirect` enum は apex と無関係 (www 制御専用)

`RedirectTypes` = `www` / `non-www` / `both`。Traefik label 生成は**この 2 条件だけ**:

- `redirect === 'www'` **かつ** host が `www.` で始まらない → `www.<host>` への redirect middleware を付ける
- `redirect === 'non-www'` **かつ** host が `www.` で始まる → non-www への redirect middleware を付ける

→ apex (`n-wasabi.org`、`www.` 始まりでない) では:
- **`www` は危険** — `www.n-wasabi.org` へ飛ばすが、そこに DNS も router も無ければ壊れる
- **`non-www` / `both` はどちらも no-op** (middleware が付かない)。`both` は「両方 redirect」でなく「**どちらにも寄せない**」の意

### API フィールドの事実 (4.1.2)

- `is_static` / `is_spa` / `publish_directory` / `static_image` / `custom_nginx_configuration` は
  **POST・PATCH どちらの `allowedFields` にもある**。`is_static` / `is_spa` / `is_force_https_enabled` は
  `removeUnnecessaryFieldsFromRequest()` で一旦落とされ、**`$application->settings` 側に個別代入**される
- ★ **`is_force_https_enabled` は POST 作成 body で直接指定できる** (`$isForceHttpsEnabled = $request->is_force_https_enabled;`)。
  作成後に PATCH する必要は仕様上は無い (ただし 302 ループは別問題 → `gotcha/coolify-https-redirect-loop.md`)
- `static_image` の enum は **`nginx:alpine` の 1 値のみ** (`StaticImageTypes`)。差し替え不可
- `custom_nginx_configuration` は **base64 必須**。未指定なら `defaultNginxConfiguration()`:
  - 非 SPA: `try_files $uri $uri.html $uri/index.html $uri/index.htm $uri/ =404;` → **`/about` で `about.html` が引ける** (実測)
  - SPA (`is_spa: true`): `try_files $uri $uri/ /index.html;`
- **`index` という API フィールドは存在しない**。index の指定は `custom_nginx_configuration` でしか変えられない

## Why

`static` は「ビルド成果物をリポジトリに置いて配る」という Coolify の最も素朴な想定に対応する build pack で、
ビルドが要る静的サイトは **`nixpacks`/`railpack` + `is_static: true` + `publish_directory`** の方が担当。
enum 名が両方 "static" 系なので混同しやすいが、**通る関数が別**:

| 設定 | 実行される関数 | ビルド | publish_directory |
|---|---|---|---|
| `build_pack: static` | `build_static_image()` | **しない** | **無視** |
| `build_pack: nixpacks` + `is_static: true` | nixpacks build → nginx へ COPY | する | **効く** |
| `build_pack: railpack` + `is_static: true` | `build_railpack_static_image()` | する | **効く** |

## How to apply

**ビルド不要の静的サイト (素の HTML/CSS) を Coolify に載せるとき**:

1. `build_pack: "static"`。`ports_exposes` / `health_check_port` は **80 以外を書いても 80 に上書きされる**ので 80 で揃える
2. **配信したいファイルだけをサブディレクトリに置き、`base_directory` でそこを指す**。
   リポジトリ root を指すと README も CI 定義も公開配信される
3. `publish_directory` を書いても**効かない**。効くと思って設計しない
4. healthcheck は `health_check_path: "/"` (or 実在する HTML) + `health_check_host: "localhost"` で通る。
   **通る理由は nginx:alpine の実 curl**。`static_image` は enum で固定なので当面は安全だが、
   「alpine だから wget で通る」という理解は**誤り** (busybox wget は localhost で落ちる)
5. `redirect` は apex 運用なら **`both` か `non-www`** (どちらも no-op)。**`www` にすると apex が壊れる**

**ビルドが要る静的サイト (Astro/Vite 等)** なら `static` は使えない。
`nixpacks`/`railpack` + `is_static: true` + `publish_directory` か、`dockerfile` build pack を選ぶ。

## 関連

- [`tool-quirk/coolify-api.md`](../tool-quirk/coolify-api.md) — API の癖全般 / spec 乖離
- [`gotcha/coolify-healthcheck-localhost-ipv6-vs-node-bind.md`](../gotcha/coolify-healthcheck-localhost-ipv6-vs-node-bind.md) — 同じ IPv4-only bind でも curl の有無で生死が分かれる
- [`gotcha/coolify-https-redirect-loop.md`](../gotcha/coolify-https-redirect-loop.md) — 新規 app は force_https を PATCH しても 302 ループを踏む
