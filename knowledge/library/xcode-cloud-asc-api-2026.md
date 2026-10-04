---
title: Xcode Cloud を ASC API / Webhook / ci_scripts から外部制御する (2026-10 時点の仕様と癖)
category: library
tags: [xcode-cloud, app-store-connect-api, ciBuildRuns, webhook, testflight, flutter, ci-scripts]
created: 2026-10-05
project: global
sources:
  - https://developer.apple.com/documentation/appstoreconnectapi/post-v1-cibuildruns
  - https://developer.apple.com/documentation/appstoreconnectapi/cibuildruncreaterequest
  - https://developer.apple.com/documentation/xcode/configuring-webhooks-in-xcode-cloud
  - https://developer.apple.com/documentation/xcode/webhook-payload
  - https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds
  - https://developer.apple.com/documentation/xcode/environment-variable-reference
  - https://developer.apple.com/documentation/xcode/writing-custom-build-scripts
  - https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference
  - https://developer.apple.com/documentation/xcode/configuring-your-xcode-cloud-workflow-s-actions
  - https://github.com/flutter/flutter/issues/187710
model-era: sonnet-5
---

## Context
wasawasa から Xcode Cloud を起動して Flutter iOS (bloom dev) をビルド・配布する構成の事前調査 (2026-10-05)。詳細と PJ 固有の含意は `projects/wasawasa/.knowledge/research-xcode-cloud-trigger.md`。ここには横断的な癖だけ置く。Apple docs は SPA なので `developer.apple.com/tutorials/data/documentation/{appstoreconnectapi,xcode}/<slug>.json` を直読みした (`library/apple-developer-docs-json-endpoint.md`)。

## What
- **起動 `POST /v1/ciBuildRuns`**: body は `relationships.workflow` (ciWorkflows の id、必須相当) + 任意の `relationships.sourceBranchOrTag` / `buildRun` (再実行) / `pullRequest`、`attributes.clean` (bool) のみ。**ブランチ名の文字列は渡せない**。`sourceBranchOrTag` は `{type: scmGitReferences, id}` で、id は `GET /v1/scmRepositories/{id}/gitReferences` (params は limit / fields / include のみ、name 絞り込みなし) を引いて `name` / `canonicalName` で突合する。**環境変数・inputs・任意パラメータを渡す口は無い**
- **読み取り**: `GET /v1/ciBuildRuns/{id}` の `executionProgress` = PENDING / RUNNING / COMPLETE、`completionStatus` = SUCCEEDED / FAILED / ERRORED / CANCELED / SKIPPED、`number` = Xcode Cloud ビルド番号。`ciBuildRuns` の全体一覧は無く `GET /v1/ciWorkflows/{id}/buildRuns` (`sort`, `limit`, `filter[builds]`)。`GET /v1/ciBuildRuns/{id}/actions` → ciBuildActions → `.../artifacts` → `ciArtifacts.downloadUrl` (期限付き)。artifact の fileType は ARCHIVE / ARCHIVE_EXPORT / LOG_BUNDLE / RESULT_BUNDLE / TEST_PRODUCTS / XCODEBUILD_PRODUCTS / STAPLED_NOTARIZED_ARCHIVE
- **`ciProducts` の作成 API は無い** (GET / DELETE のみ)。`ciWorkflows` は POST / PATCH / DELETE あり。**ASC の App レコード作成 API も無い** (`POST /v1/apps` は CREATE 不可)。product / SCM 接続 / App レコードは Xcode か ASC の UI で 1 回作る
- **完了通知は Webhook**: Xcode Cloud 固有の webhook が別にある (ASC → Xcode Cloud → Settings → Webhooks、または Xcode の Report navigator で Manage Webhooks)。product あたり最大 5 本、`BUILD_CREATED` / `BUILD_STARTED` / `BUILD_COMPLETED` の 3 イベントごとに HTTPS POST (JSON、`ciBuildRun.id` / `number` / `executionProgress` / `completionStatus` 含む)。作成時の入力は **name と URL のみ** (secret 欄の記載なし = 署名検証の記載なし)。応答は 30 秒以内に 2xx、でなければ再送。**ASC API の `POST /v1/webhooks` (HMAC `x-apple-signature`) は別物**で、イベント型に Xcode Cloud ビルド完了は無い (`BUILD_UPLOAD_STATE_UPDATED` 等のみ)
- **ビルド番号**: Xcode Cloud が product ごとに 1 から自動採番 (`CI_BUILD_NUMBER`)、TestFlight / App Store もこの値を使うと公式に明記。API で次番号は変えられず、変更は ASC UI の Xcode Cloud → Settings → Build Number (Admin / App Manager)。**起動ごとに外部の値を使う公式手段は無い**。`ci_post_xcodebuild.sh` で xcarchive 内の CFBundleVersion を書き換える回避策は OSS の PR 1 件の記述のみで未検証 (署名との整合も未確認)
- **ci_scripts**: `ci_post_clone.sh` / `ci_pre_xcodebuild.sh` / `ci_post_xcodebuild.sh` を Xcode project / workspace と同じディレクトリの `ci_scripts/` に置く (Flutter なら `ios/ci_scripts/`)。ワークフローの Environment で任意の環境変数を設定でき、「Secret」指定でログ上 `**********` に伏せられる。ネットワークは HTTP proxy 経由 (`HTTP(S)_PROXY` が設定済み)。egress IP 範囲は公開されている (2026-02-10 更新: 57.103.0.0/22, 57.103.64.0/18 ほか IPv6)。使える環境変数: `CI_BUILD_ID` (= ciBuildRuns の id と同形式の UUID。同一値と断定する Apple の記述は無し)、`CI_BUILD_NUMBER`、`CI_BRANCH`、`CI_COMMIT`、`CI_START_CONDITION` (manual 等)、`CI_WORKFLOW`、`CI_AD_HOC_SIGNED_APP_PATH` / `CI_APP_STORE_SIGNED_APP_PATH` (archive 後)、`CI_XCODEBUILD_EXIT_CODE`
- **Ad Hoc**: archive action の Deployment Preparation は UI 上 None / TestFlight (Internal Testing Only) / TestFlight and App Store の 3 択。それとは別に `CI_AD_HOC_SIGNED_APP_PATH` が存在し、Xcode Cloud は archive 後に Ad Hoc export を自動で試みるという forum 報告がある (失敗すると archive action ごと失敗)。**Ad Hoc を狙って選ぶ公式手段は未確認**
- **Flutter**: 公式 CD docs の `ios/ci_scripts/ci_post_clone.sh` は Flutter を git clone → `flutter precache --ios` → `flutter pub get` → brew で cocoapods → `pod install`。**Flutter 3.44.1 + FlutterFire (SPM) は Xcode Cloud の package 解決で失敗 (flutter/flutter#187710)、3.44.2 で修正済み**。Xcode が archive するので `--dart-define` は直接渡せず、`flutter build ios --config-only --dart-define-from-file=...` で `ios/Flutter/Generated.xcconfig` に `DART_DEFINES` を書かせる (二次情報)

## Why
Xcode Cloud は「起動 = ワークフロー + ブランチだけ」「完了通知 = Webhook (署名なし)」「番号 = Apple が採番」という設計で、CI に任意の入力を渡す前提になっていない。GitHub Actions の `workflow_dispatch inputs` と同じ発想で設計すると破綻する。

## How to apply
- 起動パラメータはビルド側 (`ci_scripts`) が `CI_BUILD_ID` / `CI_BRANCH` で外部 API に問い合わせて取る (pull 型)。Secret 環境変数に外部 API の token を入れる
- 完了検知は Webhook を受けても payload を信用せず `GET /v1/ciBuildRuns/{id}` で再取得して確定する (署名が無いため)。Webhook 取りこぼしに備え polling を併用
- ビルド番号は Xcode Cloud の `number` を正として読み戻す。外部採番と二重管理しない
- 新規 bundle id (dev flavor 等) は先に ASC の UI で App レコード + Xcode Cloud product を作る必要がある (API 不可)
