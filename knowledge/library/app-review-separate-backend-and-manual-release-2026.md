---
title: 審査ビルドを別 backend に繋ぐ・承認後に切り替える件の App Review 規約上の扱いと、手動リリース (Pending Developer Release) の期限
category: library
tags: [app-store, app-review, guidelines, manual-release, pending-developer-release, backend, bloom]
created: 2026-10-15
project: global
sources:
  - https://developer.apple.com/app-store/review/guidelines/  # Last Updated: June 8, 2026 (2026-10-15 取得)
  - https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option
  - https://developer.apple.com/help/app-store-connect/reference/app-and-submission-statuses/app-store-version-statuses
---

## Context

bloom で「互換を崩す版を本番に出さずに審査を通す」ため、審査中の版のリクエストだけ審査用 backend に振り分け、承認後に外して手動リリースする案の規約確認 (2026-10-15、curl で本文取得)。

## What

- ガイドライン本文 (2026-06-08 版) に「審査時と公開後で接続先 backend を変えること」を直接禁じる条項は無い (全文を backend / server / review で検索して該当なし。不在の確認であって Apple の明示的な許可ではない)
- 関係する条項:
  - 2.1(a): login があるなら demo account 情報を出し、「turn on your back-end service!」。ガイドライン末尾の提出前チェックにも「Enable backend services so that they're live and accessible during review」
  - 2.3.1(a): hidden / dormant / undocumented な機能を入れない。新機能は Notes for Review に具体的に書き、審査で触れられること
  - 2.5.2: 機能を変えるコードのダウンロード・実行は不可 (backend のデータ・設定の差し替えは対象外と読めるが、明文の解釈は無い)
- → 審査用 backend は「同じコード・同じ機能で、データだけ分離」に留めるのが規約上安全。審査 backend だけに見える機能・画面を作ると 2.3.1 の「審査と実際が違う」に近づく
- 手動リリース: 「Manually release this version」を選ぶと承認後 `Pending Developer Release`。**期限の記載は無い**。30 日を超えると Apple からリマインダーメール。リリース後 App Store 反映まで最大 24 時間。ASC API でもリリース可 (`appStoreVersionReleaseRequests`)

## Why

Apple は審査中の動作 (backend 稼働・demo account) を要求するが、サーバー側の構成までは規定していない。問題になるのは「審査で見たものと利用者が得るものの乖離」で、その判定は 2.3.1 の領分。

## How to apply

- 審査用 backend は本番と同じ commit をデプロイし、違いは DB (デモデータ入り) と env だけにする
- Notes for Review には「サインイン後、以下の招待リンクを貼るとデモ用グループに入れる」等の手順を具体的に書く (2.3.1 の具体性要件)
- 承認後は「振り分けを外す -> 本番側 server を新版対応にする -> Release This Version」の順。30 日リマインダーは期限ではないので急がなくてよい
