# Knowledge Index

Generated: 2026-05-26

_Run `python3 Muraki/scripts/gen-knowledge-index.py` to regenerate._

## library
- [Aisaba 自作スタック (Appera + Nexom + aisaba_platform)](library/aisaba-stack.md) — `global` — ユーザーが運用している Web アプリ群 (apps.aisaba.net 配下: portfolio_manager / permissions / file_size_sense / カレンダー / MeishiLink ダッシュボード
- [Anthropic Claude API のデータ保持・学習利用ポリシー (2026年5月時点)](library/anthropic-api-data-retention.md) — `global` — 個人ヘルスケア・メンタル系アプリで Claude API を使うとき、「ユーザーの会話を Anthropic 側にどれだけ残されるか」「学習に使われるか」を正確に知っておく必要がある。ZDR (Zero Data Retention) を契
- [Auth.js v5 + PrismaAdapter + SQLite (Magic Link + Google) 最小構成](library/authjs-v5-prisma-sqlite.md) — `global` — Next.js 15 App Router + Prisma + better-sqlite3 で Auth.js v5 を使い、
- [better-auth 1.6.x (2026-05) — Next.js + Prisma + Magic Link + OAuth 最小構成](library/better-auth-2026.md) — `global` — Next.js (App Router) + Prisma + SQLite で「Magic Link + Google OAuth + DB session」を最小コストで組みたい場面。Auth.js v5 が長らく beta のままなの
- [better-auth 1.6.x + Hono + Drizzle + SQLite 構成 (Anonymous Plugin 含む 2026-05)](library/better-auth-hono-drizzle-sqlite.md) — `global` — Web アプリで「Hono + Drizzle + SQLite + better-auth」スタックを採用する場面、特に Anonymous Plugin で「名前のみのゲスト運用」をする場合。既存 [`library/better-au
- [Capacitor HealthKit プラグインの現状 (2026年5月)](library/capacitor-healthkit-plugins.md) — `global` — Capacitor iOS アプリから HealthKit の睡眠ステージ・心拍・HRV などを読みたい。2026年5月時点でどのプラグインが現役か、何ができて何ができないかを確定したい。
- [Capacitor 8 + Next.js 16 で iOS ハイブリッドアプリを組む (2026年5月時点)](library/capacitor-nextjs-ios-2026.md) — `global` — 個人開発で「iPhone がメイン、Web も触れる」ハイブリッドアプリを最小コストで作る場面。Expo (React Native) との二択で Capacitor を選んだ時。
- [Claude Haiku 4.5 API 仕様 (2026年5月時点)](library/claude-haiku-4-5-api.md) — `global` — 秘書系・チャット・軽量エージェント用途で Claude を使う際の最新スペック。Haiku 4.5 をデフォルトに据える時の参照。
- [Cloudflare Tunnel 1 本でオンプレ全公開 (HTTPS + SSH, 2026年5月構成)](library/cloudflare-tunnel-2026.md) — `global` — オンプレ Ubuntu サーバー (`192.168.3.17`、SoftBank光) で運用している全サブドメイン (aisaba.net / appily.run / ceez7.com / SSH) を Cloudflare Tunn
- [日本の救急 時間帯別分布データ (令和元年→令和5年比較)](library/jp-emergency-time-distribution.md) — `global` — 日本の救急業務の「平均値」ではなく「分布形状」が必要なとき (UX訴求コピーや緊急度判定設計の根拠)。消防庁公式統計から確定したロングテール構造データ。
- [日本のOHCA場所別生存率と現着時間の真実 (JAMA 2019・東京令和5年・全国Utstein 2018)](library/jp-ohca-location-survival.md) — `global` — 救急関連プロダクトで「平均14分」「20分以上ロングテール」の上位の話を求めるとき。OHCAの生存率は **発生場所で18倍違う**。EMS現着時間自体の場所差は1分しかない。設計判断を誤らないために必読。
- [日本のOHCA・救急医療マクロ統計 (2023年実績)](library/jp-ohca-stats.md) — `global` — 日本向け救命系アプリ・防災UX設計時の基礎データ。2026年5月時点で確認した最新公式値。
- [Lucia v3 は 2026-03 で完全 deprecated — 新規 PJ で採用してはならない](library/lucia-deprecated-2025.md) — `global` — Web アプリで session-based 認証を組む際、Lucia v3 を選びたくなる場面。session DB + cookie の純度を取る設計で過去人気があったが、**作者 pilcrow が 2024-10 (= 2025年1
- [Next.js 15 + Prisma + better-sqlite3 + Coolify スタック概要](library/nextjs15-prisma-sqlite-coolify.md) — `global` — Next.js 15 + Prisma 6.x + better-sqlite3 + SQLite を 1コンテナで Coolify デプロイする構成。`output: "standalone"` で薄い image を作り、SQLite 
- [vCard 日本語名刺生成 (vCard 3.0 + 振り仮名)](library/vcard-japanese.md) — `global` — 日本向け Web 名刺アプリで、iOS/Android 連絡先に取り込める .vcf を Node で生成する。
- [OMATASE-demo Pre-design Research Summary](../projects/omatase-demo/.knowledge/00-research-summary.md) — `omatase-demo` — OMATASE (URL 共有で待ち合わせ・イベント進行) MVP の設計**前**リサーチ。Hono + Drizzle + SQLite + better-auth(anonymous) を初採用するため、各 API の存在確認・連携パ

## pattern
- [AI 振り返り対話のセッション設計と階層型メモリ](pattern/ai-reflection-dialog-memory.md) — `global` — 夜の振り返り (evening reflection) を AI と対話で行う UX。Stoic / Rosebud / Mindsera の 2025-2026 設計と、長期運用での memory アーキテクチャ。
- [aisaba.net 系の視覚デザイン言語](pattern/aisaba-design-language.md) — `global` — aisaba.net・apps.aisaba.net・portfolio_manager 等、ユーザー (Touri Aida) が運営する複数サイトで一貫した視覚言語が使われている。新規 UI を作る・既存サイトに追加コンポーネントを差し
- [CBT 系 AI コンパニオン対話の設計パターン (System prompt + 安全境界)](pattern/cbt-ai-companion-dialog.md) — `global` — メンタルウェルネス / 生活リズム改善 / AI 秘書系アプリで、LLM (Claude Haiku 4.5 等) を「相談相手」として配置する場面。Woebot / Wysa / Earkick / Replika / Pi / Rose
- [Coolify アプリのデプロイ詰まり調査フロー](pattern/coolify-deploy-debug-flow.md) — `global` — Coolify でデプロイしてアプリが想定通りアクセス可能にならないとき、原因が「ビルド」「コンテナ起動」「環境変数」「Traefik routing」「Cloudflare proxy」のどこにあるか切り分けるパターン。MeishiLin
- [パニック時 UI の設計トークンと挙動原則 (緊急アプリ向け)](pattern/emergency-ui-design-tokens.md) — `global` — 「人が倒れた」「火災が起きた」など極度のパニック時にユーザーが操作する UI の設計。
- [Postgres + Node でのアプリ層 envelope encryption パターン (Coolify セルフホスト)](pattern/envelope-encryption-postgres-node.md) — `global` — 個人ヘルスケア / メンタル系アプリで「ログ取らない・コード公開可・at-rest 暗号化・LLM 処理時のみ in-memory 復号」を実装したい。バックエンドは Coolify (Docker) + Postgres、ソロ運用。
- [入力フォームモーダル (BottomSheet/Dialog) の視認性 BP (2026)](pattern/form-modal-readability-bp.md) — `global` — Modal / Bottom Sheet 内に入力フォームを置く場面で「文字が見えにくい」「階層が弱い」「フォーカスが分からない」と感じる根因は**たいてい設計トークンの欠陥に集約**される。Atender redesign で実装後に T
- [グリッド・テーブル罫線 BP (時間割/カレンダー/データ表示)](pattern/grid-table-borders-bp.md) — `global` — 時間割・カレンダー・テーブル系 UI で「セルがバラバラに見える」「表として認識されない」体感が出るのは、罫線設計が以下のどちらかに偏った時:
- [iOS ハイブリッドアプリの push 通知スケジューリング (Local + APNs 併用)](pattern/ios-push-scheduling-hybrid.md) — `global` — 「毎日特定時刻 (起床・就寝・服薬) に通知」「+ AI 生成のチェックインを動的に push」両方が必要な iOS アプリで採用する設計。Capacitor / Expo / React Native いずれでも適用可能。
- [LLM 対話アプリの安全境界スタック (regex 先行 + tool 強制 + AAD 暗号化)](pattern/llm-dialog-safety-stack.md) — `global` — メンタルウェルネス / 生活リズム / AI 秘書系で LLM (Claude Haiku 4.5 等) と長時間対話する。
- [LLM 生成 Push 通知の現実的アーキテクチャ (iOS APNs + Claude Haiku)](pattern/llm-push-notification-architecture.md) — `global` — 「起床コーチ」「就寝リマインド」「夜の振り返り誘導」など、AI が文面を個別生成する push 通知を iOS に飛ばす場面。レイテンシ・コスト・UX の現実的トレードオフ。
- [最小限の SNS レイヤ (Friend + Room) を Prisma + 単一 endpoint で設計するパターン](pattern/minimal-social-layer-friend-room.md) — `global` — 「友達追加 + グループ (ルーム) + 共有カレンダー」程度の軽量 SNS 機能を、既存アプリに**追加機能として後付け**するときの最小構成。LINE / Penmark / TimeTree のような **個人 ID + 招待リンク 
- [モバイル first PWA の bottom tab bar 実装ベストプラクティス (2025-2026)](pattern/mobile-first-bottom-tab.md) — `global` — モバイル first Web アプリ (PWA / Capacitor / SwiftUI 移行予定 SPA) で、下端 bottom tab bar を実装するときの 2025-2026 BP。Atender redesign 調査でまと
- [LLM Ready な気分ログのスキーマと UX (Daylio / How We Feel / Finch 系)](pattern/mood-log-schema-llm-ready.md) — `global` — 気分ログ / 感情記録 / journaling 系アプリの構造化スキーマを設計するとき、後段で LLM (Claude 等) が読みやすい形にする方法。Daylio / How We Feel / Finch / Reflectly の 
- [SQLite で polymorphic Feature プラグイン基盤を組む (kind + JSON config)](pattern/polymorphic-feature-plugin-sqlite.md) — `global` — エンティティに「種類の違う付加機能」を 0..N 個アタッチしたいケース。例:
- [ポータブル設計のリアルタイム救命系スタック (Hono + Prisma+PostGIS + 自前 ws + Expo Push)](pattern/portable-realtime-rescue-stack.md) — `global` — 「位置共有 + 即時通知 + 双方向 WS」を要求する救命/防災/オンコール系アプリ。
- [Spotify 歌詞風縦スクロール UI を framer-motion なしで実装するパターン](pattern/spotify-lyrics-scroll-css-only.md) — `global` — Spotify / Apple Music 歌詞のような「今のラインが画面中央に固定、過去は薄く流れ、未来は下に並ぶ」UI を React + Tailwind で実装したいケース。Atender の Today 画面 (現在進行中の授業を
- [TanStack Query の invalidation を設計 doc にマトリクスで書く](pattern/tanstack-query-invalidation-matrix.md) — `global` — TanStack Query (旧 React Query) で SPA を組むとき、「mutation 後にキャッシュが古いままで、ブラウザリロードしないと反映されない」 (= invalidate 漏れ) は最頻ハマり所。
- [TanStack Query Polling 設計 (refetchInterval 値の選び方と動的停止)](pattern/tanstack-query-polling-strategy.md) — `global` — リアルタイム性が必要だが SSE / WebSocket を導入するほどではない場面 (MVP・遅延数秒許容・stateless backend) で、TanStack Query の `refetchInterval` で polling
- [時間割アプリ UX パターン (Penmark 系 / 学生向け / 2024-2026)](pattern/timetable-app-ux-patterns.md) — `global` — 日本市場で学生向け時間割アプリを設計するとき、Penmark (日本最大級・大学生 100 万人超ユーザー) を主参考に、海外カレンダーアプリ (Notion Calendar / Fantastical) の連続イベント表現と組み合わせる
- [Touri 流の「シンプル + 並列拡張」設計パターン](pattern/touri-design-philosophy.md) — `global` — ユーザー (Touri Aida) が CGI 時代から積み上げてきたコードベース (ceez7 / マネログ) を読んで抽出した設計パターン。本人いわく「**目的に対してなるべくシンプルな実装と、汎用性・拡張性に長けた設計**」。AI コ
- [Web 先行 → Capacitor 後付けを見越した Next.js 設計 (output: 'export' 縛り)](pattern/web-first-capacitor-later-design.md) — `global` — 「最終的に iOS ハイブリッドアプリにしたいが、最初は Web 完結 MVP で検証したい」場面。tomori Phase 1 で採用した戦略。Phase 1 で Server Actions / middleware を 1 箇所でも使

## gotcha
- [better-auth テスト helper の cookie は Hono signed cookie 形式を再現する必要がある](gotcha/better-auth-test-cookie-must-match-hono-signed-format.md) — `global` — better-auth 1.6.x + Hono 4.12.x の API を Vitest + `app.request()` でテストする際、テスト helper で「Session 行を直接 prisma で作って Cookie ヘッ
- [chrome-devtools MCP の fill は React controlled input の onChange を発火させない](gotcha/chrome-devtools-mcp-fill-react-controlled-input.md) — `global` — `mcp__chrome-devtools__fill` (またはツール呼び出し名 `fill`) で React の controlled input (`<input value={state} onChange={...} />`) 
- [Cloudflare Tunnel 経由は loopback 接続 — Nginx の IP allowlist に 127.0.0.1 を入れ忘れると 403](gotcha/cloudflare-tunnel-nginx-allowlist-loopback.md) — `global` — aisaba_platform の Nginx vhost には Cloudflare edge IP からのみ受け付ける allowlist が `cloudflare_only.conf` として include されている (`all
- [Coolify on Cloudflare の 307/302 HTTPS リダイレクトループ](gotcha/coolify-https-redirect-loop.md) — `global` — Coolify (`coolify.aisaba.net`) で新規 application を立てると、HTTP/2 307 or 302 で **location が自分自身** という無限リダイレクトループを起こす。Cloudflar
- [Coolify は private GitHub repo を default で clone できない (Public Repo 用フロー)](gotcha/coolify-private-repo-cannot-clone.md) — `global` — Coolify (`coolify.aisaba.net`) で **Public Repo** build pack (`POST /applications/public`) を使ってアプリを作成し、`git_repository: "
- [Coolify で全パス self-redirect ループになる時の復旧手順](gotcha/coolify-traefik-stale-label-loop.md) — `global` — Coolify (Traefik) で Dockerfile アプリをデプロイ。`fqdn` 個別指定 (例 `https://meishilink.appily.run`) + server に `wildcard_domain=http
- [設計 doc にテスト用 app export path を明示しないと Developer と Reviewer が分離して詰む](gotcha/design-must-specify-app-export-path-for-tests.md) — `global` — Atender MVP の Reviewer 召集で、`apps/api` のテストを設計 doc 根拠で生成 → Vitest を実行 → 81 件中 76 件 fail。失敗の原因はすべて単一: テスト helper が import 
- [設計書の error code 表記が「明示」か「例示」か曖昧で実装/テストが食い違う](gotcha/design-spec-implicit-vs-explicit-error-codes.md) — `global` — 設計書 §4.x で API エラーレスポンスを以下のように列挙していた:
- [Expo の `process.env.EXPO_PUBLIC_*` は **直接参照** しないと bundle に inline されない](gotcha/expo-public-env-static-replacement.md) — `global` — Expo (SDK 50+) は `process.env.EXPO_PUBLIC_*` を build時に **literal 値で static 置換** する。これにより mobile bundle / web bundle に en
- [Hono の app.request() はテスト経路で HTTP ヘッダ値を Latin-1 (ByteString) に制限する](gotcha/hono-app-request-header-latin1-constraint.md) — `global` — better-auth + Hono + Vitest で「匿名サインインに日本語名を `x-guest-name` ヘッダで渡す」テストを書こうとすると、
- [Hono の errorMiddleware で AppError の status を読み損ねると全部 500 になる](gotcha/hono-error-middleware-apperror-status.md) — `global` — Hono で `class AppError extends Error { status, code, ... }` を定義し、route handler で `throw new AppError(409, "EMAIL_TAKEN",
- [jsdom の getBoundingClientRect は常に 0 を返す](gotcha/jsdom-getboundingclientrect-zero.md) — `global` — OMATASE デザインモック (Vitest + RTL + jsdom) のレビューで、設計 §10.9 にあった
- [Leaflet マップを使う画面で modal/overlay は z-index 1000 超え必須](gotcha/leaflet-zindex-vs-modal.md) — `global` — React アプリで Leaflet (react-leaflet) の地図と同一スクリーン内に modal / overlay を出した時、Tailwind の `z-20` や `z-50` 程度だと **modal が地図の Zoom
- [Next.js route の baseUrl は req URL ではなく env 変数 (PUBLIC_BASE_URL) 由来](gotcha/nextjs-route-baseurl-env-vs-req.md) — `global` — vcard route handler が `PHOTO;VALUE=URI:` に絶対 URL を埋め込む。Reviewer のテストで `new Request("https://example.com/yamada/vcard")` 
- [PostgreSQL enum と text の比較は明示 cast が必要 (raw SQL)](gotcha/postgres-enum-text-cast-in-raw-sql.md) — `global` — Prisma で `enum Tier { TIER1 TIER2 TIER3 }` を定義し、設計書通りの raw SQL で半径検索 + Tier フィルタを書いた:
- [Prisma + better-sqlite3 + Next.js 15 standalone を Coolify Docker で動かす完全形](gotcha/prisma-coolify-dockerfile.md) — `global` — Next.js 15 + Prisma + better-sqlite3 + SQLite を Coolify (Traefik、1コンテナ standalone build) にデプロイする構成。`output: "standalone"
- [Prisma $queryRaw が PostGIS geography カラムをデシリアライズできない](gotcha/prisma-geography-deserialize-error.md) — `global` — Prisma schema で `geom geography` を `Unsupported("geography")` で宣言している場合、
- [app の PrismaClient シングルトンが .env.test の DATABASE_URL を pin して、テスト毎の DB 切替が効かない](gotcha/prisma-singleton-pinned-to-env-test-database-url.md) — `global` — Atender Phase 4 (v3) の Reviewer 召集で、API テスト 110 件中 101 件が `PrismaClientInitializationError: Error querying the database:
- [TanStack Router factory export 時のテスト用 memory history 注入](gotcha/tanstack-router-factory-test-memory-history.md) — `global` — Atender web (Vite + React + TanStack Router) で Reviewer が RTL + jsdom 環境のテストを書く際、router を Provider 経由で立ち上げる helper を作ろうと
- [pickFirstFunction の Object.values fallback で Prisma.sql タグ等を誤拾い](gotcha/test-pickfirstfunction-fallback-traps.md) — `global` — Reviewer がテスト生成時、対象モジュールの export 名が設計書に明示されていない場合、
- [testcontainers + postgres で 「ready to accept connections」を 1 回だけ待つと早期接続失敗](gotcha/testcontainers-postgres-double-ready-log.md) — `global` — testcontainers で PostgreSQL を spawn し、global setup で `Wait.forLogMessage(/database system is ready to accept connections
- [Vitest で Expo/React Native モジュールを import する時の落とし穴](gotcha/vitest-expo-rn-import-pitfalls.md) — `global` — Tsunagu Mobile (Expo + React Native + TypeScript) で Reviewer が Vitest テストを生成した際、Zustand store のテストで実装をimportした瞬間に
- [vi.mock("node:fs/promises") は specifier が違うと当たらない](gotcha/vitest-mock-fs-specifier-mismatch.md) — `global` — Reviewer が Next.js App Router の route handler (例: `src/app/u/[handle]/logo/route.ts`) のテストを書く際、ファイル読み込みを mock するために `vi.
- [Vitest server テストで app の DB に対し setup で migration を流さないと "no such table" で全 fail する](gotcha/vitest-server-setup-must-migrate-app-db.md) — `global` — Hono + Drizzle + better-sqlite3 + better-auth スタックで、設計 doc に「起動時 migration を `src/server/index.ts` で実行する」と書くと、**テストでは `i

## tool-quirk
- [block-bash-amp.sh は heredoc/tee 内のコード文字列の論理積もブロックする](tool-quirk/bash-amp-hook-blocks-heredoc-content.md) — `global` — Muraki ルートに置かれた `block-bash-amp.sh` フックは、
- [chrome-devtools MCP は Chrome for Testing を headless 運用、project 並列は userDataDir 分離](tool-quirk/chrome-for-testing.md) — `global` — chrome-devtools MCP で Web ページを閲覧/操作する場面。普段使い Chrome のプロファイルを汚染せず、Notion など要ログインのサイトではセッションを保持し、かつ複数 Claude Code セッションを *
- [cloudflared tunnel login は 1 zone しか cert.pem に入れない — 複数 zone は API token を使う](tool-quirk/cloudflared-tunnel-login-multi-zone.md) — `global` — `cloudflared tunnel login` で発行される `~/.cloudflared/cert.pem` (Origin CA cert + Argo Tunnel API service token) は、`cloudfla
- [Codex CLI 内蔵 imagegen ツール (gpt-image-1) の使い方](tool-quirk/codex-cli-imagegen-tool.md) — `global` — Codex CLI 経由で OpenAI Images API (gpt-image-1) を叩きたい場面。`OPENAI_API_KEY` 未設定、ChatGPT サブスク認証 (`auth_mode: chatgpt`) のみという前提
- [codex exec はデフォルト read-only サンドボックス、scaffolding 系は --full-auto 必須](tool-quirk/codex-exec-sandbox-default.md) — `global` — Developer (Codex) に空 worktree から Vite/React プロジェクトを scaffold させたら、`apply_patch` が `writing is blocked by read-only sandb
- [Codex CLI / Gemini CLI を並列レビューに使うときの癖](tool-quirk/codex-gemini-cli-parallel.md) — `global` — 複数 LLM で同じコードを独立レビューさせ、結果を JSON で集約したい。
- [Coolify API の癖と未公開仕様](tool-quirk/coolify-api.md) — `global` — Coolify (オンプレ Ubuntu サーバ `coolify.aisaba.net`) を HTTP API 経由で操作する際、公式 OpenAPI と実装の食い違い・公式 docs に書いてない癖が多数ある。MeishiLink デ
- [画像生成は Codex (Images2 / gpt-image-1) 優先、Gemini Nanobanana より高品質](tool-quirk/image-generation-models.md) — `global` — CLAUDE.md の役割分担では「Gemini = 画像などビジュアル面」と一般原則が書かれている。しかし画像生成タスクに限って言えば、ユーザーの実体験に基づく判断として **Codex (内部的に OpenAI Images-2 / g

## other (uncategorized)
- [Atender Pre-design Research Summary](../projects/atender/.knowledge/00-research-summary.md) — `atender` — 調査日: 2026-05-13 / 調査者: researcher (Gemini + WebFetch + WebSearch + `npm view`)。
- [Atender Redesign UI/UX Research (Phase 2)](../projects/atender/.knowledge/01-redesign-research.md) — `atender` — 調査日: 2026-05-15 / 調査者: researcher (Gemini + WebSearch)。
- [Atender 入力 UX / 視認性 BP リサーチ (Phase 3)](../projects/atender/.knowledge/02-input-ux-research.md) — `atender` — 調査日: 2026-05-18 / 調査者: researcher (Gemini + Codex)。
- [Atender Phase 4 Pre-design Research — Rooms / Friends / Today UX 全面刷新](../projects/atender/.knowledge/03-v3-rooms-friends-research.md) — `atender` — 調査日: 2026-05-26 / 調査者: researcher (Gemini + ローカル既存コード読解)。
