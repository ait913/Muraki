---
title: Apple PLA 更新未承諾だと xcodebuild -exportArchive が「No signing certificate iOS Distribution」で落ちる
category: gotcha
project: atender
tags: [ios, xcodebuild, app-store-connect, codesign, testflight]
created: 2026-10-29
sources:
  - sessions/2026-10-29-dbbd5b80.md
---

## Context

atender build 21 を CLI 一気通貫 (archive → export → altool upload、ASC API キー + cloud-managed 署名) で TestFlight に上げようとした。archive は成功、export が失敗。

## What

export ログに 2 行:

```
error: exportArchive Unable to process request - PLA Update available
error: exportArchive No signing certificate "iOS Distribution" found
```

2 行目が本命に見えるが原因は 1 行目。Apple Developer **Program License Agreement (PLA) が更新**されており、Account Holder が developer.apple.com で承諾するまで、`-allowProvisioningUpdates` + ASC API キーによる cloud-managed 配布証明書の発行が拒否される。ローカルに Distribution 証明書が無い環境 (`security find-identity -v -p codesigning | grep -ci distribution` = 0) では export が必ず落ちる。

## Why

- PLA 承諾は Account Holder の人間操作のみ (API キーの権限 Admin でも代行不可)
- cloud-managed 証明書は export 時に生成されるので、archive までは通る (署名は開発証明書)。失敗が後段で出るため「証明書が無い」と誤診しやすい

## How to apply

- export が `No signing certificate "iOS Distribution"` で落ちたら、まずログに `PLA Update available` が無いか grep する
- あれば Touri に https://developer.apple.com/account の Agreement 承諾を依頼 (App Store Connect のトップにも同じバナーが出る)。承諾後、archive は再利用して export から再実行すればよい
- 無人実行の前提として「PLA が最新か」はリリース前チェックリストに入れる (Apple は WWDC 後や規約改定時に更新する)
