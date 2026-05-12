---
title: Aisaba 自作スタック (Appera + Nexom + aisaba_platform)
category: library
tags: [aisaba, appera, nexom, frontend, backend, deployment]
created: 2026-05-10
project: global
sources:
  - /Users/touri/Documents/Creatives/Developments/Projects/Appera
  - /Users/touri/Documents/Creatives/Developments/Projects/Nexom
  - /Users/touri/Documents/Creatives/Developments/aisaba_platform
---

## Context

ユーザーが運用している Web アプリ群 (apps.aisaba.net 配下: portfolio_manager / permissions / file_size_sense / カレンダー / MeishiLink ダッシュボード等) は、**フロント・バックエンド・デプロイ基盤すべてオリジナル実装**。今後これらに触れる際の道標。

## What

### Appera (TypeScript フロントライブラリ)

- 場所: `Developments/Projects/Appera`
- 仮想DOMベース、すべて `aElement` 基底クラスを継承
- 主要クラス: `aDivElement` `aH1〜H4Element` `aPElement` `aFormElement` `aInputElement` `aImgElement` `aLinkElement` `aButtonElement` `aWindowElement` `aWindow` (モーダル) `ModalManager` `aDOM`
- 差分エンジンは `aWrapper`。containerをidで掴み、key→id→apv→indexの順で要素マッチ
- クリックは **委譲型**: `apv` データ属性経由で `aWrapper.handler_map` にルーティング (各要素に addEventListener しない)
- フォーカス中の input は値を上書きしない (差分時の安全機構)
- ビルド: `tsc` で `dist/` に JS + d.ts。npm パッケージ `appera` として消費される

### Nexom (Python WSGI フレームワーク)

- 場所: `Developments/Projects/Nexom` / 公式ドキュメント: https://nexom.aisaba.net/documents / GitHub: https://github.com/ait913/Nexom (MIT)
- **CLI**: `python -m nexom start-project --main-name app --auth-name auth` で雛形生成 → `python -m nexom run` で全アプリ起動 (デフォルト :8080)
- ルーティングはデコレータ不使用・**クラスベース**: `Router(Get(path, handler), Post(...), Static(...))`、`add_middleware(*ms)` でミドルウェア登録
- パスセグメント: 静的 / 動的 `{param}` / ワイルドカード `{"*"}`
- ハンドラシグネチャ: `(Request, dict[str, str|None]) -> Response | dict` (dict は自動 JSON)
- **Request** (`nexom.app.request`): `read_body()` `body()` `json()` `form()` `files()` `content_type()` `cookies`。wsgi.input は一回しか読めずキャッシュされる。`files()` と他のbody parser (json/form/read_body) は併用不可
- **Response** (`nexom.app.response`): `Response` `HtmlResponse` `JsonResponse` `Redirect` (302) `ErrorResponse` (テンプレHTMLエラーページ)。`append_header()` で重複可
- **Middleware** (`nexom.app.middleware`): `__call__(request, args, next_) -> Response`。`MiddlewareChain` が外→内に合成。組み込み `CORSMiddleware` あり (origin検証・preflight・ヘッダ設定)
- **Auth** (`nexom.app.auth`):
  - `AuthService` — 独立した JSON API サーバ (signup/login/logout/verify)。`db_path` `log_path` `ttl_sec` (デフォルト 7日) で初期化
  - `AuthClient` — HTTP 経由で AuthService を叩く。各アプリが認証検証時に使用
  - `AuthDBM` — SQLite (users/sessions/permissions)
  - `Permissions` — グループ単位の権限ヘルパ。階層レベル 0-100
  - パスワード PBKDF2-SHA256、トークン HMAC、`_nxt` cookie
- **Build** (`nexom.buildTools.build`): `start_project()` `create_app()` `create_auth()` `create_config()`。`AppBuildOptions` で生成設定カスタマイズ
- **Run** (`nexom.buildTools.run`): `run_project(project_root, app_names=None, dry_run=False)`。`wsgi.py` + `gunicorn.conf.py` 両方ある dir をアプリとして検出。**POSIX 限定** (Windows は明示エラー)。subprocess で gunicorn 起動
- ドキュメント章 (https://nexom.aisaba.net/documents/<name>): GetStarted / Auth / AuthTemplate / Request / Response / Template / Path / Middleware / Cookie / Database / ParallelStorage / User / HttpStatusCodes / Build / Run / Error / Log / ObjectHTML

### aisaba_platform (デプロイ基盤)

- 場所: `Developments/aisaba_platform`
- レイアウト: `services/` (各 Nexom アプリ) + `public/` (静的) + `gateway/` (nginx vhost)
- 主要サービス:
  - `auth` — 認証サーバ (127.0.0.1 ローカル待受)
  - `aisaba_user` — user.aisaba.net ログインゲート
  - `apps` — apps.aisaba.net ランチャ。`/{app_id}/{*}` で `applications/` 配下のアプリにディスパッチ
  - `aisaba_main` — ポートフォリオ・ブログ公開サイト
  - `uploader` — チャンク (5MB) アップロード + SHA256 検証
- 内蔵アプリ: `applications/` 配下に `portfolio_manager` / `permissions` / `calender` / `file_size_sense` / `thread_app` 等。`AppsDBM.auto_register_apps()` で自動登録
- 各サービスは gunicorn + 個別ポートで常駐。systemd は `nexom@<service>` テンプレートユニットで管理
- データ (logs/db/uploads) は `data/` 配下 — リポジトリ外、シンボリックリンク

### デプロイフロー

1. `aisaba_platform` の `dev` ブランチに push
2. codeserv (vscode aisaba 環境) に入って pull
3. `systemctl restart nexom@<service>` で対象サービス再起動

## Why

- フロント: 既存FW (React等) を使わず、軽量・必要十分・自分の制御下に置く設計思想。委譲型クリックとフォーカス保護差分は SPA で頻出する痛点を仮想DOM側で吸収するため
- バックエンド: WSGI 互換にすることで gunicorn / nginx と素直に連携。ルーティングをクラスベースにしたのはデコレータの暗黙性を避けるため
- 基盤: マルチアプリを単一ドメイン (apps.aisaba.net) 配下に並べ、認証は中央 (auth サービス) に集約。アプリ追加は `applications/` に置けば自動登録される横展開設計

## How to apply

- **フロント変更**: `appera` の `a*Element` を組み立てて `aWrapper.render([...])`。クリックは `click_event` プロパティに割り当てる (apv は自動付与、同一ツリー内重複に注意)
- **バックエンド新規ルート**: 該当アプリの `routing.py` で `Get(path, handler)` 等を追加。dict を返せば JSON、画面なら `HtmlResponse`、リダイレクトは `Redirect('/path')`、エラーは `ErrorResponse`
- **詳細仕様で迷ったら**: https://nexom.aisaba.net/documents/<モジュール名> (Path/Request/Response/Middleware/Auth/Cookie/Database/ParallelStorage/User/Template/Build/Run/Error/Log/ObjectHTML)
- **新規アプリ追加**: `services/applications/<app>/` を作り `AppRouter` 定義 → 自動登録される。起動ポートは `gunicorn.conf.py` で指定
- **認証が必要なエンドポイント**: `AuthClient` で `_nxt` cookie のトークンを auth サーバに問い合わせて検証
- **デプロイ確認**: dev push → codeserv pull → `systemctl restart nexom@<service>` の3ステップ。restart 後は journalctl でログ確認
- **デバッグ**: chrome-devtools MCP でログイン状態を保ったままアプリ画面を踏破可能 (今回 portfolio_manager の編集はこの手段で実施)
