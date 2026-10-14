---
title: GitHub Actions を外から起動・追跡する API と GitHub App の仕様 (2026-10)
category: library
project: wasawasa
tags: [github-actions, github-app, workflow-dispatch, artifacts, environments]
created: 2026-10-14
sources:
  - https://github.blog/changelog/2026-02-19-workflow-dispatch-api-now-returns-run-ids
  - https://raw.githubusercontent.com/github/rest-api-description/main/descriptions/api.github.com/api.github.com.json
  - https://docs.github.com/en/rest/authentication/permissions-required-for-github-apps
  - https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments
  - https://docs.github.com/en/actions/reference/limits
---

## Context
wasawasa が GitHub Actions を司令塔として呼ぶ前提の確認 (2026-10-14)。

## What
- workflow dispatch (POST /repos/{o}/{r}/actions/workflows/{id}/dispatches): body に `return_run_details: true` を付けると 200 + `{workflow_run_id, run_url, html_url}`。付けないと従来どおり 204 空。inputs は最大 25 プロパティ・合計 65,535 文字。permission = Actions: write。
- dispatch は「ファイルが default branch に存在し workflow_dispatch トリガを持つ」ことが前提 (docs: This trigger only receives events when the workflow file is on the default branch)。feature ブランチ専用ファイルは 404 になる報告あり (コミュニティ情報、公式未確認)。
- run 状態 GET /actions/runs/{id} = Actions: read。cancel = Actions: write (202 / 409)。成果物一覧 /runs/{id}/artifacts、DL /actions/artifacts/{id}/zip は 302 で `Location` の URL が **1 分で失効**、zip のみ。Actions: read。
- Contents API の取得は Contents: read、`Accept: application/vnd.github.raw+json` で生本文、`?ref=<sha>` で commit 指定。
- installation token: JWT で POST /app/installations/{id}/access_tokens、寿命 1 時間。body の `permissions` / `repositories` で絞れる (App に無い権限は要求不可)。2026-04-27 から stateless 形式 `ghs_APPID_JWT` に段階移行 → 40 桁固定を仮定しない。
- artifact: 既定保持 90 日 (upload-artifact は 1-90)、1 job 500 個。保存容量クォータは Free 500MB / Pro 1GB / Team 2GB / Enterprise 50GB (サポートでも増やせない)。per-artifact サイズ上限は公式未発見。
- Actions limits: included minutes Free 2000 / Pro,Team 3000、macOS 同時 5 (Free/Pro/Team)。REST は PAT 5,000/h。
- Environments: 私有 repo で environment secrets は Pro/Team/Enterprise 必須。deployment branches/tags 制限も私有では Pro/Team。reviewers は最大 6、self-review 禁止可。環境 secrets は当該 environment を参照する job のみ。
- Firebase App Distribution upload (releases:upload, `X-Goog-Upload-Protocol: raw`) のサイズ上限は公式に記述なし (非公式: 2048MiB / 150MB の食い違いあり)。

## Why
dispatch の run id 取得が公式化され、起動後の run 特定のための推測 (時刻・inputs 相関) が不要になった。

## How to apply
dispatch は return_run_details 必須。artifact は 1 分 URL をその場で取り、保管は wasawasa 側か下流に即送る。Firebase の実サイズ上限は大きい成果物で実測する。
