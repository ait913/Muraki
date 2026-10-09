---
title: iOS 通知の種別別オン/オフはアプリ内トグル + サーバー側フィルタで実装する (OS 設定に種別粒度は無い)
category: library
tags: [ios, apns, push, notification-settings, UNNotificationSettings, providesAppNotificationSettings]
created: 2026-10-09
project: bloom
sources:
  - https://developer.apple.com/documentation/usernotifications/unnotificationsettings
  - https://developer.apple.com/documentation/usernotifications/unauthorizationoptions/providesappnotificationsettings
  - https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/usernotificationcenter(_:opensettingsfor:)
---

## Context
Bloom「通知の強化」(コメント / リアクション / 投稿 / ビーコン等を種別ごとにユーザーが ON/OFF) の設計前リサーチ。「アプリ内トグルはサーバーが送らないだけでよいか」を Apple 一次ドキュメントで確認した。

## What
- `UNNotificationSettings` の設定項目は app 全体 (`authorizationStatus` / `alertSetting` / `soundSetting` / `badgeSetting` / `lockScreenSetting` / `notificationCenterSetting` / `timeSensitiveSetting` / `showPreviewsSetting` 等) だけで、**種別・カテゴリ単位のユーザー設定を表すプロパティは無い**。`UNNotificationCategory` はアクションボタン・グルーピング用で、設定アプリにトグルとしては出ない。
- 種別別の ON/OFF をユーザーに提供するには **アプリ内 UI + サーバー側で送信前にフィルタ** (または送らない) が唯一の実装経路。OS 側は「全部 ON / 全部 OFF」しか持たない。
- `requestAuthorization(options:)` に `.providesAppNotificationSettings` (iOS 12+) を足すと、設定アプリの当該アプリ通知ページに「アプリ内の通知設定」ボタンが出て、タップで `UNUserNotificationCenterDelegate.userNotificationCenter(_:openSettingsFor:)` が呼ばれる (`notification` は設定アプリ発だと nil)。任意だが、OS 設定からアプリ内トグルへの導線が付く。

## Why
APNs は「送る / 送らない」をサーバーが決め、端末は届いたものを表示するだけ。種別の抑制を端末側 (`willPresent` で握りつぶす) でやると、バックグラウンド着信は OS が直接表示するので抑制できない。

## How to apply
- 種別トグルは **サーバーの user 設定 (per-user、必要なら per-group) に保存し、fan-out 直前に宛先から外す**。クライアントは設定の読み書きだけ。
- OS 権限 (`authorizationStatus`) はアプリ内トグルの上位にあるので、アプリ内設定画面には「OS で通知が OFF」の状態表示 + 設定アプリへの導線 (`openSettingsURLString`) を並べる。
- `.providesAppNotificationSettings` を足す場合は delegate に `openSettingsFor` を実装し、アプリ内設定画面へ遷移させる (未実装だとボタンだけ出て何も起きない)。
