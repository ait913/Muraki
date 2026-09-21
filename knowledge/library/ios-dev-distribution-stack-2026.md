---
title: iOS 「dev環境」構築の現状確認 (Firebase App Distribution / FlutterFire / Flutter flavor / Coolify branch deploy / ASC API ad-hoc自動化, 2026-09時点)
category: library
tags: [flutter, ios, firebase, crashlytics, flavor, coolify, app-store-connect-api, ad-hoc, provisioning]
created: 2026-09-22
project: global
sources:
  - https://firebase.google.com/docs/app-distribution/register-additional-devices
  - https://firebase.google.com/docs/app-distribution/ios/set-up-for-testing
  - https://firebase.google.com/docs/app-distribution/ios/distribute-cli
  - https://firebase.google.com/docs/app-distribution/get-set-up-as-a-tester
  - https://pub.dev/packages/firebase_core
  - https://pub.dev/packages/firebase_crashlytics
  - https://firebase.google.com/docs/ios/setup
  - https://firebase.google.com/docs/ios/app-store-data-collection
  - https://docs.flutter.dev/deployment/flavors-ios
  - https://dart.dev/libraries/core/environment-declarations
  - https://github.com/flutter/flutter/issues/142976
  - https://github.com/flutter/flutter/issues/183902
  - https://coolify.io/docs/applications/ci-cd/github/preview-deploy
  - https://raw.githubusercontent.com/coollabsio/coolify/main/openapi.yaml
  - https://developer.apple.com/documentation/appstoreconnectapi/post-v1-devices
  - https://developer.apple.com/documentation/appstoreconnectapi/post-v1-profiles
  - https://developer.apple.com/documentation/appstoreconnectapi/post-v1-bundleids
  - https://developer.apple.com/forums/thread/126016
model-era: sonnet-5
---

## Context
Bloom (Flutter 3.47 iOS 専用、Coolify ホスト) に「dev 環境」(別 flavor / 別配布経路 / Firebase Crashlytics 等) を作る検討の事前リサーチ。設計前の事実確認のみ。

## What

### Firebase App Distribution (iOS)
- **2026-09時点でも Ad Hoc/Enterprise 前提は変わらず**。テスターは Web (Safari) 経由で「Firebeseプロファイル」をインストール→UDID を Firebase が収集→開発者にメール通知、という手順が現行 (TestFlightのような自動配布ではない)。ネイティブ「Firebase App Tester」アプリは存在しない (Web clip のみ)。
- UDID は Console の「Export Apple UDIDs」(CSV) または fastlane プラグイン `firebase_app_distribution_get_udids` で**プログラム的にも取得可能**。ただし取得後の Apple Developer Portal への登録・プロビジョニングプロファイル更新・再ビルドは**手動** (自動連携なし)。
- CLI: `firebase appdistribution:distribute <ipa> --app <id> [--groups|--testers] [--release-notes]`。GitHub Action `wzieba/Firebase-Distribution-Github-Action` は 2026 も活動中だが、**token 認証は非推奨化が進行中、Service Account 移行が推奨**。
- 無料枠: テスター上限 500 人 (グループ単位 200 人)、配布バージョン上限 1000/アプリ、アプリデータ保持 150 日。

### FlutterFire (firebase_core / firebase_crashlytics)
- **iOS 最小デプロイターゲットが iOS 15 に上がっている** (旧来の iOS 11/12 対応版から変更済)。Bloom の Podfile は既に `platform :ios, '15.0'` なので**互換 OK**。
- **SPM が現在の公式推奨インストール方法**、CocoaPods は代替として継続サポート (ただし `Firebase` 統合 pod は v9 以降非推奨、個別 product pod を直接参照)。Bloom は Podfile ありなので CocoaPods 継続が無難。
- `flutterfire configure --ios-build-config=<Config> --ios-out=<path>` で flavor 別 `GoogleService-Info.plist` の出力先を分けられる (複数 build config を横断して同一 Firebase App に紐付けるのが典型パターン)。Runner への build phase 自動追加は CLI が対応 (`--ios-build-config` 指定時)。
- Crashlytics の Dart 例外捕捉は `FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError` + `PlatformDispatcher.instance.onError` の両方登録が公式推奨 (片方だけだと非同期エラーを取り逃す)。
- **App Privacy 申告**: Crashlytics 単体は installation UUID ベースで「ユーザーに紐付かない」区分が基本 (Crash Data / Device ID, not linked)。**開発者がカスタムキー/user id を crash report に付与すると「ユーザーに紐付く」扱いに変わる** — 運用次第で申告内容が変わる点は要注意。

### Flutter iOS flavor (公式)
- 公式手順 (`docs.flutter.dev/deployment/flavors-ios`, 2026-09-10更新) は Xcode Scheme + Build Configuration (`Debug-<flavor>`/`Profile-<flavor>`/`Release-<flavor>`) を手動作成する方式。Bundle ID / App名 / アイコンは Build Settings (per-configuration) で切替。**dart-define や xcconfig 経由の自動生成は公式手順に含まれず、手動 Xcode 操作が必須**。
- `bool.fromEnvironment` 系の compile-time 定数は Dart 公式 (`dart.dev/libraries/core/environment-declarations`) が「production compilers can completely remove the condition and its body」と明記 — **tree-shake される根拠は公式ドキュメントで確認済み**。
- `--dart-define-from-file` は `flutter build ipa` で使えなかった不具合 (flutter/flutter#142976) が **2024年に fix 済で CLOSED**。2026-09時点で現行対応とみなしてよい (関連の Xcode build 中の環境変数露出問題 #136444 は別issue、要別途確認)。

### iOS debug ビルドの配布制約
- **iOS 14+ で確定: debug (JIT) ビルドは Flutter tooling / Xcode 以外から起動不可**。ホーム画面タップでの起動は「In iOS 14+, debug mode Flutter apps can only be launched from Flutter tooling, IDEs with Flutter plugins or from Xcode.」というエラーで拒否される。2026-03 に立てられた flutter/flutter#183902 (この制約の緩和要望) でも同じ挙動が前提として記載されており、**2026-09 時点でも現行の制約**。
- → **dev配布ビルドは `--release` か `--profile` で作る必要がある** (`--debug` は配布不可)。

### Coolify branch別デプロイ (API確認済、openapi.yaml実物ベース)
- `POST /applications/private-github-app` で別ブランチ追従の2つ目 Application を作成可能。必須: `project_uuid`, `server_uuid`, `environment_name`or`environment_uuid`, `github_app_uuid`, `git_repository`, `git_branch`, `build_pack`。`is_auto_deploy_enabled` / `is_preview_deployments_enabled` はアプリ単位のフラグ (openapi.yaml 実物で確認)。
- Preview Deployments (PR単位) は固定ブランチ運用とは別機能。有効化すると PR ごとに使い捨てpreviewが作られクローズ/マージで自動削除。固定 `dev1` ブランチ追従のニーズには**不要** (Application を2つ作る方が単純)。
- Env一括投入: `PATCH /applications/{uuid}/envs/bulk` (`data: [{key, value, is_preview, is_literal, is_multiline, is_shown_once}]`)。
- Postgres DB作成: `POST /databases/postgresql`。必須は `server_uuid`, `project_uuid`, `environment_name`or`environment_uuid`。他は任意 (`postgres_user`/`postgres_password`/`postgres_db`/`instant_deploy` 等)。

### Apple SIWA 別 bundle id / ASC API 自動化
- 別 bundle id で SIWA を使う場合、App ID 登録時に SIWA capability を有効化し「Group with existing primary App ID」を選べる。**ただしフォーラム報告では、グループ化した2番目のApp IDは iPhone の「Apple でサインイン」設定一覧に出ない・メール共有/非共有プロンプトが出ないなど不具合報告があり (developer.apple.com/forums/thread/126016)、確定した公式挙動保証ではない** — 実機検証必須。
- ASC API で以下は確認済 (JSON docs直取得、2026-09-22実測):
  - `POST /v1/bundleIds` — 必須 `identifier`, `name`, `platform` (任意 `seedId`)
  - `POST /v1/bundleIdCapabilities` — 必須 `capabilityType` (SIWAは `APPLE_ID_AUTH` — CapabilityType enum に実在確認済), relationship `bundleId` 必須
  - `POST /v1/devices` — 必須 `name`, `platform`, `udid`
  - `POST /v1/profiles` — 必須 `name`, `profileType`, relationship `bundleId`・`certificates` 必須、`devices` は任意 (ad hoc は指定要)。**profileType の enum値 `IOS_APP_ADHOC` は複数の二次情報で一致 (公式 enum ページ自体は取得できず、一次確認は未完了)**
  - いずれもバルク登録エンドポイントは無し (1件ずつ POST)
- `xcodebuild -exportArchive -allowProvisioningUpdates` は自動証明書/プロファイル更新のみ。**新規デバイスの自動登録には別フラグ `-allowProvisioningDeviceRegistration` が必要**、かつこれは**ビルドマシンに物理/ネットワーク接続されたデバイスのみ**が対象 — リモートテスターのUDID登録は対象外 (UDID取得自体は別経路が必要)。

### 実装で判明した追加事実 (2026-09-22、bloom dev 環境)

- **`flutterfire configure` は Xcode に flavor 別 Build Configuration が複数あると `--yes` でも「Build configuration / Target」の対話プロンプトで停止する** (非対話実行だと無限待ち)。pbxproj を触らせたくない場合は使わず、`firebase apps:sdkconfig IOS <appId> --project <id>` の出力を `GoogleService-Info.plist` として保存し、Dart の `FirebaseOptions` は plist から生成する (apiKey / GOOGLE_APP_ID / GCM_SENDER_ID / PROJECT_ID / STORAGE_BUCKET / BUNDLE_ID)
- **Flutter 3.47 は Firebase プラグインを CocoaPods でなく Swift Package Manager で解決する** (`ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage`)。`Podfile.lock` に Firebase は出ず、`ios/Pods/FirebaseCrashlytics/upload-symbols` は存在しない。実体は **`app/build/ios/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols`** (flutter build 後に生成。DerivedData ではない)
- **Firebase CLI の `projects:create` は Google Cloud の利用規約未同意アカウントでは `Callers must accept Terms of Service` で失敗**。Console で 1 度プロジェクトを作らせると同意が済む。CLI に `projects:delete` は無く、孤児 project は `~/.config/configstore/firebase-tools.json` の access_token で Cloud Resource Manager `DELETE /v1/projects/{id}` を叩く
- **`bool.fromEnvironment` の const 折り畳みは「文字列リテラルの除去」にも効く**: prod バイナリに dev ホストや `/dev/*` ルートの文字列を残さない負のコントロールを通すには、allowlist などのデータも `kDevTools ? [...] : []` / `kDevTools ? 'host' : ''` の const で書く。素の const リストに dev 文字列を入れると (コードが到達不能でも) `strings` に残る
- ASC API で `POST /v1/bundleIds` + `POST /v1/bundleIdCapabilities` (PUSH_NOTIFICATIONS / ASSOCIATED_DOMAINS) は 201 で通った。`APPLE_ID_AUTH` は API では `PRIMARY_APP_CONSENT` しか設定できず、既存 primary へのグループ化は Developer portal の UI のみ
- `firebase login` は Claude Code の `!` 実行だとブラウザが開けず「コード方式」になる (URL を開いて得たコードを `firebase login <code>` で渡す)

## Why
Bloom の dev 環境設計 (別 flavor + Firebase App Distribution + Coolify branch app + SIWA 別bundle id) は、上記のうち「Firebase側は完全自動化できない (UDID収集後の手動プロビジョニングが残る)」「iOS debugビルドは配布不可 (release/profile必須)」「SIWAのグループ化App IDは実機不具合報告あり」の3点が設計に直接影響する不確定/制約要素。

## How to apply
設計時にこの3点を前提に置く: (1) Firebase App Distributionを使うなら UDID登録〜再ビルドの手動ループをワークフローとして明示する、(2) dev配布ビルドは `--release`/`--profile`、(3) SIWA別bundle idはグループ化の実機動作を早期に検証してから前提にする。
