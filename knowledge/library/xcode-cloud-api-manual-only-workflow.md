---
title: Xcode Cloud を API で「手動開始のみ」にするには manualBranchStartCondition を使う (branchStartCondition は null にできず、残すと手動ビルドが 409)
category: library
project: wasawasa
tags: [xcode-cloud, app-store-connect-api, ciWorkflows, ciBuildRuns, testflight]
created: 2026-11-04
sources:
  - sessions/2026-10-31-76c68c35.md (#91〜#92、wacha G-T3)
  - https://developer.apple.com/documentation/appstoreconnectapi/ciworkflow
---

## Context

wasawasa は環境の「アプリアップロード」で `POST /v1/ciBuildRuns` (workflow + `sourceBranchOrTag`) を打ってビルドを起こす。Xcode のウィザードが作る既定 workflow は Start Conditions に「Branch Changes: main」を持つ。これを API で手動専用に直そうとして 3 回ハマった (wacha、2026-11-04)。

## What

- `PATCH /v1/ciWorkflows/{id}` で `branchStartCondition: null` を送っても **無視される** (200 で値はそのまま)。`{}` や `{source:null}` は 409 `ENTITY_ERROR.ATTRIBUTE.REQUIRED`。空パターン `{source:{isAllMatch:false,patterns:[]}}` は通るが、下の 409 は消えない
- `branchStartCondition` が**何か入っている**と、そのパターンに合わないブランチの手動ビルドは `POST /v1/ciBuildRuns` が 409 `ENTITY_ERROR.ATTRIBUTE.INVALID`: 「The manual build cannot be created because the branch ”main” is not associated with the workflow. Specify the branch in the start condition of the workflow.」(pointer `/data/attributes/sourceBranchOrTag`)。wasawasa は失敗理由 `xcode_cloud_rejected` にし、ログの error 本文は redact するので、原因はこの文を直接叩いて初めて読めた
- **正解**: `manualBranchStartCondition: {source:{isAllMatch:true,patterns:[]}}` を PATCH する。これを入れると Apple 側が `branchStartCondition` を **null に落とす** (自動と手動は種類ごとに排他)。結果は Xcode の UI で Branch Changes を消したのと同じ形 (bloom の workflow と同じ `branchStartCondition: null`) になり、`main` の手動ビルドが通る
- Archive の Deployment Preparation は `actions[].buildDistributionAudience`: `APP_STORE_ELIGIBLE` = TestFlight and App Store、`INTERNAL_ONLY` = TestFlight (Internal Testing Only)、null = None。`actions` は配列ごと全置換 (name / actionType / scheme / platform / isRequiredToPass も入れる)
- API で**できない**こと: product の作成 (`POST /v1/ciProducts` が無い。GitHub の Grant Access も人)、Build Number の初期値、Webhooks。Bundle ID の登録 (`POST /v1/bundleIds`、capability は `POST /v1/bundleIdCapabilities`) はできる

## Why

Xcode Cloud の手動ビルドは「workflow が知っているブランチ」にしか作れない仕様で、自動開始条件があるとそのパターンが「知っているブランチ」の全てになる。手動開始条件 (Xcode 15 以降の UI の「Manual」) が API では `manual*StartCondition` で、これが有るときは全ブランチ (isAllMatch) を手動で起こせる。

## How to apply

新規アプリを wasawasa に載せるとき (RUNBOOK「新しいアプリをアプリアップロードに載せる」): Xcode のウィザードは**既定のまま完了**し、Start Build は押さず、API で 1 回 PATCH する:

```json
{"data":{"type":"ciWorkflows","id":"<workflow>","attributes":{
  "name":"TestFlight (manual)",
  "manualBranchStartCondition":{"source":{"isAllMatch":true,"patterns":[]}},
  "actions":[{"name":"Archive - iOS","actionType":"ARCHIVE","scheme":"Runner","platform":"IOS","isRequiredToPass":true,"buildDistributionAudience":"APP_STORE_ELIGIBLE"}]}}}
```

手元の実装: scratchpad の `asc_bundleid.py` (`wfpatch` / `wfmanual` / `startrun`) を `Muraki/.tmp/wasawasa-asc.env` の Admin キーで。wasawasa のツールにする価値あり (§16-1 の 3 を人手から外せる)。`xcode_cloud_catalog` の `start_on_push` が true の workflow は本番で手動ビルドが 409 になり得るので、env_update の warning 候補。
