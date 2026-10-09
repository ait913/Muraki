---
title: iOS 位置許可の「使用中 → 常に」2 段取得の実挙動 (requestAlwaysAuthorization / Provisional Always / CLServiceSession、iOS 18.4・26.5 実測)
category: library
project: global
tags: [ios, core-location, always-authorization, provisional-always, clservicesession, requestAlwaysAuthorization, onboarding, flutter]
created: 2026-10-09
sources:
  - https://developer.apple.com/documentation/corelocation/cllocationmanager/requestalwaysauthorization().md
  - https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services
  - https://developer.apple.com/documentation/corelocation/clservicesession-pt7n.md
  - https://developer.apple.com/documentation/corelocation/suspending-authorization-requests.md
  - https://developer.apple.com/videos/play/wwdc2024/10212/
  - https://developer.apple.com/forums/thread/845158
  - https://developer.apple.com/forums/thread/823157
  - iPhoneOS26.5.sdk CoreLocation/Headers/CLLocationManager.h (requestAlwaysAuthorization の Discussion)
  - 実測: xcodegen 最小アプリ (scratchpad locprobe) を iOS 18.4 / 26.5 シミュレータで `simctl privacy grant location` 後に起動 (2026-10-09)
---

## Context

Bloom (Flutter、iOS 15.0+) のオンボーディングで、notDetermined から直接 `requestAlwaysAuthorization()` を呼ぶと **Provisional Always** (`authorizationStatus == .authorizedAlways` だが実体は使用中のみ) になり、後日 OS の 2 回目プロンプトで「使用中のみ」に落とされて全画面ゲートが発火する問題の設計前調査。「使用中 → 常に」の 2 段で取る時の正確な OS 挙動を一次資料 + 実測で確定した。

## What

### 1. 2 段取得 (WhenInUse 取得済 → `requestAlwaysAuthorization()`)

- Apple 公式: 「If the user grants When In Use permission after your app calls requestWhenInUseAuthorization(), then calling requestAlwaysAuthorization() **immediately prompts** the user to request Always permission.」選択肢は「Keep Only While Using (delegate 通知なし) / Change to Always Allow (delegate に authorizedAlways)」
- **実測 (iOS 18.4 / 26.5 sim)**: WhenInUse 状態で `requestAlwaysAuthorization()` → 即時に「"<App>" を使用していないときでも位置情報の使用を許可しますか?」+ `NSLocationAlwaysAndWhenInUseUsageDescription` の文言。ボタンは **「"使用中のみ許可" のままにする」/「"常に許可" に変更」** の 2 択
- **1 回限り**: SDK ヘッダ「An application which currently has "when-in-use" authorization and has never before requested "always" authorization may use this method to request "always" authorization **one time only**. Otherwise ... this method will do nothing.」+ 公式 doc「After your app calls this method, further calls have no effect.」→ 昇格プロンプトを消費した後は no-op。再誘導は設定アプリ (`UIApplication.openSettingsURLString`) しかない
- **前提条件**: Info.plist に `NSLocationWhenInUseUsageDescription` と `NSLocationAlwaysAndWhenInUseUsageDescription` の両方 (欠けると「do nothing」)。ヘッダ追記「If your app is not currently in use, this method will do nothing」(前景で呼ぶこと)。`UIBackgroundModes: location` は要求条件ではない (プロンプト表示には不要)
- **Allow Once (1 度だけ許可) を選ばれると以後の `requestAlwaysAuthorization()` は無視される** (temporary authorization)。Allow Once は delegate に authorizedWhenInUse が来て、非使用になると notDetermined に戻る
- 無効化要因 (第三者報告、Apple 回答なし): `NSLocationDefaultAccuracyReduced = true` を Info.plist に置くと昇格プロンプトが出ない (iOS 26.6.1 実機 / 26.4 sim、forums/thread/845158)。Bloom は未設定

### 2. notDetermined から直接 `requestAlwaysAuthorization()` (= Provisional Always)

- 1 回目は WhenInUse 文言で **「1 度だけ許可 / アプリの使用中は許可 / 許可しない」** の 3 択 (実測 iOS 26.5)。「アプリの使用中は許可」で Provisional Always、delegate は authorizedAlways を受ける
- 2 回目プロンプトは「Core Location prepares to deliver an event to your app requiring authorizedAlways」の時に出て、**典型的にはアプリ非起動中**。「Keep Only While Using」で authorizedWhenInUse に落ち delegate が呼ばれる。「Change to Always Allow」なら delegate 通知なし
- **Provisional かどうかを知る公開 API は無い**: `CLAuthorizationStatus` は notDetermined / restricted / denied / authorizedAlways / authorizedWhenInUse のみ (SDK 26.5 ヘッダに provisional の語は 0 件)。設定アプリは「使用中のみ」を表示するが、アプリからは authorizedAlways にしか見えない

### 3. CLServiceSession (iOS 18+) は Always 昇格の手段にならない

- `CLServiceSession` は iOS 18.0+ (`swiftc -typecheck -target arm64-apple-ios15.0` で「only available in iOS 18.0 or newer」を確認)。deployment target 15 のアプリからは `if #available(iOS 18, *)` 内でのみ使える
- 公式: 「The CLServiceSession object requests a person's authorization to meet those requirements if possible」「Always authorization will only be effective when you hold one of these, and you can only start holding one when your app is in the foreground」(WWDC24 10212)。ただし **WhenInUse 状態で `CLServiceSession(authorization: .always)` を作っても昇格プロンプトは出ない** (実測 iOS 18.4 / 26.5 sim: プロンプトなし、diagnostics は即座に `authorizationRequestInProgress=false, alwaysAuthorizationDenied=true, insufficientlyInUse=false`)
- `CLRequireExplicitServiceSession` (Info.plist、Bool=YES) は「新 API (liveUpdates 等) の反復が暗黙にプロンプトを出す」のを止めるキー。`requestWhenInUse/AlwaysAuthorization` を使う既存コードには関係ない

### 4. iOS バージョン差

iOS 13 で「初回プロンプトから Always が消え、Provisional Always と Allow Once が導入」(WWDC19 705)。iOS 14 で精度 (reduced accuracy)、iOS 16 で Control Center インジケータ、iOS 18 で CLServiceSession。**昇格プロンプトの挙動自体は iOS 13 以降不変で、Apple doc にバージョン注記は無い**。iOS 26 の変更は見つからなかった (WWDC25 に Core Location 認可セッションなし)。実測は 18.4 と 26.5 で同一

## Why

Apple は「Always は提供価値が明確になってから、使用中の後に 1 回だけ」を前提に API を設計している。notDetermined から直接 Always を要求する経路は「Provisional」で成功したように見えるが、確定は OS 任せでアプリに観測手段がない。

## How to apply

- 「常に」が必須のアプリでは **`requestWhenInUseAuthorization()` → (説明画面) → `requestAlwaysAuthorization()`** の順で呼ぶ。昇格プロンプトは即時・前景・1 回限り。結果は `locationManagerDidChangeAuthorization` で受ける (「使用中のまま」を選ばれると delegate が来ないので、タイムアウト or 前景復帰で `authorizationStatus` を再読する)
- 昇格プロンプト消費後に still whenInUse → 設定アプリ誘導しかない。「Allow Once」も同じ扱い (authorizationStatus は whenInUse のまま区別不能)
- notDetermined から直接 Always を要求する現行経路は、authorizedAlways を「設定済」と信じてはいけない (Provisional)。2 段に切り替えると Provisional 状態自体が発生しない
- ブリッジ (Flutter MethodChannel 等) で両方を 1 つの delegate に受けるなら、pending を**段階付き** (`.whenInUse(escalate:)` / `.always`) で持ち、didChange では `.whenInUse(escalate: true)` + whenInUse だけを `.always` に昇格させて `requestAlwaysAuthorization` を 1 回、fallback timer (1.5 秒) は `.always` 段だけを現状で完了する。notDetermined からの「常に」要求もこの連鎖に乗せれば Provisional を作る経路がアプリから消える (bloom `.designs/20261009-onboarding-v2-and-store-shots.md` §3-2、2026-10-09)
- シミュレータ実測の手順: `simctl privacy grant location <bundle>` で WhenInUse を事前付与 → 起動 → スクショ。**OS プロンプトは `terminate` / `privacy reset` では消えない**ので run ごとに `shutdown`→`boot` し、notDetermined 起動 (3 択プロンプト) を負のコントロールにする
