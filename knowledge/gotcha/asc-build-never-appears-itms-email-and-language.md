---
title: TestFlight に「Upload succeeded」した build が ASC に出てこない時はメール (ITMS-90683 purpose string) / App Store の「言語」は developmentRegion で決まる
category: gotcha
project: global
tags: [apple, app-store-connect, testflight, itms-90683, purpose-string, info-plist, developmentRegion, localization]
created: 2026-10-08
sources:
  - sessions/2026-10-08-2cbf2e19 (bloom 0.2.0 build 28 / 29)
  - https://developer.apple.com/documentation/uikit/protecting_the_user_s_privacy/requesting_access_to_protected_resources
---

## Context

bloom 0.2.0 の審査提出。`xcodebuild -exportArchive`(destination=upload) は「Upload succeeded」で終わり、`altool --validate-app` も no errors なのに、ASC API `GET /v1/builds` に build 28 / 29 が 70 分出てこなかった。同時に Touri から「App Store の情報の言語が英語になっている」。

## What

1. **アップロード後の検証失敗は API にも ASC の画面にも出ず、開発者メール (ITMS-xxxxx) だけ**。build 28 は `ITMS-90683: Missing purpose string in Info.plist` (`NSPhotoLibraryUsageDescription`) で捨てられていた。
   - 原因は 0.2.0 で入れた `background_downloader` (と既存の `image_picker_ios`) が `PHPhotoLibrary` を参照すること。Apple はシンボル参照だけで要求する (「アプリが使っていなくても必要」)。
   - 過去の実績 (15〜30 分で VALID) を 2 倍超えたら、処理遅延でなくメールを疑う。`altool --validate-app` は **この種の post-processing 検証を再現しない** (通る)。
2. **App Store 商品ページの「言語」はメタデータの locale ではなく、バイナリの `CFBundleDevelopmentRegion` と `*.lproj` から導出される**。Flutter 既定は `$(DEVELOPMENT_LANGUAGE)` = pbxproj `developmentRegion = en` で、ja.lproj が無いので「英語」と表示される。ASC 側の primaryLocale = ja、description が日本語でも変わらない。

## How to apply

- 新しい plugin を足したリリースでは、アーカイブ後に `strings Runner.app/Frameworks/*/<name> | grep PH`、または `ios/.symlinks/plugins/*/ios` を `PHPhotoLibrary|PHAsset|import Photos|CNContact|EKEvent|AVCaptureDevice` で grep して、該当する `NS*UsageDescription` を Info.plist に揃えてからアップロードする。purpose string は**実際の用途**を書く (bloom は S6 のアイコン画像選択で写真ライブラリを実使用していた。「使っていません」と書くと虚偽になる)。
- 「Upload succeeded」から 40 分経って `GET /v1/builds?filter[version]=N` が空なら、Touri に開発者メール (nwasabi.dev@gmail.com) の ITMS 通知を見てもらう。ステータスページや IPA 再検証で時間を溶かさない。
- 日本語アプリは `Info.plist` に `CFBundleDevelopmentRegion = ja` + `CFBundleLocalizations = [ja]`、pbxproj の `developmentRegion = ja` / `knownRegions` に `ja` を入れる (bloom は 0.2.0+29 で対応)。
