---
title: 本番 Crashlytics は Firebase CLI の MCP サーバー経由で API 取得できる (Web console 不要)
category: tool-quirk
project: global
tags: [firebase, crashlytics, mcp, firebase-tools, flutter, ios, crash]
created: 2026-10-09
sources:
  - "firebase-tools 15.30.2 (/opt/homebrew/lib/node_modules/firebase-tools/lib/mcp/tools/crashlytics)"
  - "sessions/2026-10-09-9f2cb1ff.md (bloom 0.2.0 起動時クラッシュの特定)"
---

## Context

本番アプリのクラッシュ (Crashlytics) を調べたいが、ブラウザで Firebase console を触るのは重い / 自動化できない。Firebase CLI (`firebase-tools`) に **Crashlytics の MCP ツール**が同梱されていて、CLI の MCP サーバーを stdio で駆動すれば API でクラッシュを引ける。`gcloud` や個別の API 鍵は不要 (`firebase login` 済みのアカウントで動く)。

## What

- `firebase mcp --only crashlytics,core --dir <firebase.json のあるdir>` を stdio で起動し、JSON-RPC で叩く。`.firebaserc` に `{"projects":{"default":"<project>"}}`、空の `firebase.json` を置いた作業 dir があればよい。
- 主なツール (すべて `appId` 必須 = Firebase App Id、例 bloom prod iOS `1:816295547805:ios:d8f4e3d754256343855574`):
  - `crashlytics_get_report` — `report` に `topIssues` / `topVersions` / `topOperatingSystems` / `topAppleDevices` 等、`filter` に `intervalStartTime`/`intervalEndTime` (ISO8601、過去 90 日内) や `versionDisplayNames`。issue の id / title / subtitle / errorType / firstSeenVersion / sampleEvent / signals (SIGNAL_FRESH 等) / crashFree% を返す。
  - `crashlytics_get_issue` (`issueId`) — issue 詳細 + variants。
  - `crashlytics_list_events` — **`filter.issueId` か `issueVariantId` が必須** (無いとエラー)。イベントの device / os / memory / version / threads (ネイティブスタック) / customKeys / processState を返す。
  - `crashlytics_batch_get_events` (`names` = event resource 名の配列) — sampleEvent の詳細。
  - `crashlytics_update_issue` (state OPEN/CLOSED/MUTED) / `crashlytics_create_note` / `list_notes` も有る。
- Flutter の `FlutterError` 由来の fatal は `customKeys.flutter_error_exception` に Dart の例外型名が入る (例 `DriftRemoteException`)。`threads` は Crashlytics のネイティブ記録フレームのみで Dart スタックは空のことがある (`title: <empty stack>`) → 例外型名と firstSeenVersion で原因を絞る。

## Why

- MCP ツールは listTools に現れるが、Claude の MCP クライアントに Firebase MCP を登録していなくても、**CLI を直接 stdio で駆動すれば使える** (`initialize` → `notifications/initialized` → `tools/call`)。これで「本番クラッシュを API で取得 → コードと突合」まで一貫して自動でできる。
- Web console の手動操作 (ブラウザ自動化) より速く、権限も `firebase login` のアカウントスコープで済む。

## How to apply

- 駆動スクリプトの骨子 (Python で stdio を叩く): `subprocess.Popen(["firebase","mcp","--only","crashlytics,core","--dir",D])` に `{"jsonrpc":"2.0","id":1,"method":"initialize",...}` → `{"method":"notifications/initialized"}` → `{"id":i,"method":"tools/call","params":{"name":"crashlytics_get_report","arguments":{...}}}` を書き、`id` 一致の行を読む。`firebase.json`/`.firebaserc` を置いた一時 dir を `--dir` に渡す。
- まず `crashlytics_get_report { report: "topIssues", filter: 時間窓 }` で FATAL の issue を一覧 → `firstSeenVersion` が障害の出た版と一致するか、`SIGNAL_FRESH` (今日初出) かを見る。詳細が要れば `batch_get_events` に `sampleEvent` を渡す。
- 障害バージョンの切り分け: `firstSeenVersion` と、同じ症状が前の版に無いこと (report の version フィルタ) で「この版で入った変更が原因」を裏取りできる。bloom 0.2.0 の起動クラッシュはこれで `DriftRemoteException` / firstSeenVersion 0.2.0 を即特定した。
