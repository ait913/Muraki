---
title: ASC API キーのスコープ / Xcode Cloud webhook の単位 / Firebase 別プロジェクト SA (2026-10 時点)
category: library
project: global
tags: [app-store-connect-api, xcode-cloud, webhook, firebase-app-distribution, iam, service-account]
created: 2026-10-14
sources:
  - https://developer.apple.com/tutorials/data/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api.json
  - https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/
  - https://developer.apple.com/documentation/xcode/configuring-webhooks-in-xcode-cloud
  - https://developer.apple.com/documentation/xcode/webhook-payload
  - https://firebase.google.com/docs/projects/iam/roles-predefined-product
  - https://docs.cloud.google.com/docs/quotas/quota-project
---

## Context
複数アカウント (Apple Developer チーム / GCP プロジェクト) の鍵を 1 つのツールに登録して使い分ける設計の前提 (wasawasa, 2026-10-14)。

## What
- **ASC Team key は「チーム内の全アプリ」**。"Team API keys are applied across all apps, so app access can't be limited for an API key"。鍵の role は作成後に変更不可 (失効して作り直し)。Team key の生成は Account Holder / Admin のみ。Individual key は user の権限・アプリ範囲に従い、ユーザー 1 人 1 鍵、Provisioning 等のエンドポイントは使えない。→ 鍵の単位 = Apple Developer チーム。同一チームなら鍵 2 本を持つ意味は role 違い程度
- Xcode Cloud API (ciProducts 等) に必要な鍵 role を明記した Apple 公式ページは未発見。ロール表に "Use Xcode Cloud" 行はあるが、チェック表が text 化で欠落し列を特定できない (既存 knowledge は Admin 推奨、wasawasa は Admin 前提で 403 時に案内)
- **Xcode Cloud webhook は product 単位** (Xcode = per product / ASC = per app、最大 5 本/product)。入力は name と URL のみ。同一 URL を複数 product/webhook で使い回せるかは公式に記述なし (禁止の記述もない)。payload には `app.id` / `ciProduct.id` / `ciWorkflow.id` / `ciBuildRun.id` / `ciBuildRun.number` / `webhook.id` があるので、受信側で product 等を識別できる
- Firebase の `roles/firebaseappdistro.admin` = "Full read/write access to App Distribution resources" (viewer は read-only)。プロダクト単位の事前定義ロールで、GCP コンソールでメンバーに付与する。**別プロジェクトの SA にこのロールを付けられるか / 別プロジェクトの App Distribution API を叩けるかを明言した公式記述は未発見**
- Google の quota project: 「client-based API で呼び手が SA なら SA の属するプロジェクトが quota project」「resource-based API なら対象リソースを持つプロジェクト」。SA プロジェクトと対象プロジェクトが違う場合にどちらで API 有効化が要るかは doc に書かれず、"API not enabled" エラーが検査先プロジェクトを示す。App Distribution がどちらの型かは未確認 → 実機で別プロジェクトの SA を使い 1 回叩くのが唯一の決着手段

## Why
鍵のスコープが「チーム全体」なので、アプリごとに鍵を分ける設計は ASC 側では意味を持たない。一方 Firebase は project number が URL (`projects/{number}/apps/...`) に入るので、SA の所属プロジェクトと配布先プロジェクトが一致しない構成が起こりうる。

## How to apply
- 「環境ごとに鍵を選ぶ」ならアカウント単位 = Apple チーム / GCP プロジェクトと割り切る
- Firebase の別プロジェクト SA を許す設計にするなら、保存時検証 (releases.list を対象 project number で 1 回) で権限を実測する。事前にスタブ前提で OK と断定しない
