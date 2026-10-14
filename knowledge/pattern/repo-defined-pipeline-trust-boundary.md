---
title: リポジトリ側の手順定義ファイルを読む commit の規則 (ブランチで版管理 × 本番の保護)
category: pattern
tags: [pipeline, github, workflow-dispatch, security, wasawasa]
created: 2026-10-14
project: global
sources:
  - Muraki/projects/wasawasa/.designs/20261014-pipelines.md
  - Muraki/knowledge/library/github-actions-orchestration-api-2026.md
---

## Context
wasawasa のパイプライン設計 (2026-10-14)。環境ごとの手順を `.wasawasa.yml` (リポジトリ) で定義し、司令塔 (wasawasa) が持つ鍵 (Firebase / Apple) で配布する。GitHub environments の保護は私有リポジトリで有料プランが要り頼れない。

## What
- 「対象 ref のファイルを読む」だけだと、feature ブランチで本番の手順 (配る先・使う鍵) を書き換えられる
- 「常に既定ブランチを読む」だと、手順の変更をブランチで試せない (版管理の意図が消える)
- 両立の規則: **実行する commit (受付時に SHA へ固定) のファイルを使い、本番の環境ではその SHA が既定ブランチに含まれる時だけ実行する** (`GET /repos/{o}/{r}/compare/{default}...{sha}` の `status` が `identical` / `behind`)
- 外部 CI に ref (ブランチ名) で投げる場合、実際にビルドされた `head_sha` が受付時の SHA と違い得る。本番では**一致を要求**する (包含検査では足りない: 受付後に既定ブランチが A → B と進むと、A の定義で B の成果物を配る。両方マージ済みでも組み合わせは未検証)。commit を読めない間は先へ進めない (fail-closed)
- **配布先 (どの鍵で・どの app に・どのグループへ) は定義ファイルでなく司令塔側の登録で決める**。定義は登録済みの配布先から選ぶだけ。そうしないと未マージのブランチの定義が開発の環境から本番相当の配布先へ配れる (本番の包含検査を迂回)。本番の環境に登録した配布先は開発の環境に登録できない排他も入れる
- 定義・合成した変数・使うアカウント・配布先の登録は受付時にスナップショットし、実行中のファイル変更・設定変更を効かせない

## Why
本番の固定ブランチ = 既定ブランチの構成なら包含検査は常に通り、追加の手間が無い。人の自己申告 (「マージ済み」チェック) を機械的な検査に置き換えられる。

## How to apply
リポジトリ側の定義ファイルを外部の司令塔が読む設計 (CI 連携・デプロイ定義) では、読む commit・本番の包含検査・実際にビルドされた commit の一致 (fail-closed)・配布先の司令塔側の登録・スナップショットの 5 点を最初に設計 doc に書く (wasawasa では初稿で後半 3 点の穴を Codex に指摘された、2026-10-14)。ブランチ保護 (誰が既定ブランチに push できるか) は Git ホスティング側の前提として明記する。
