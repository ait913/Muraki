---
title: Expo SDK 57 (RN 0.86/New Arch) の地図・背景位置・WSクライアント事情
category: library
project: global
tags: [expo, react-native, maps, location, websocket, sdk57]
created: 2026-07-23
sources:
  - https://docs.expo.dev/versions/v57.0.0/sdk/maps/
  - https://docs.expo.dev/versions/v57.0.0/sdk/map-view/
  - https://docs.expo.dev/versions/v57.0.0/sdk/location/
  - https://github.com/react-native-maps/react-native-maps
  - https://raw.githubusercontent.com/expo/expo/sdk-57/packages/expo/bundledNativeModules.json
  - https://reactnative.dev/docs/network
---

## Context

omatase (位置共有アプリ) の Pre-design Research で SDK 57 + RN 0.86 (newArchEnabled) の実装ライブラリを確定した時の一次確認。

## What

- **expo-maps は SDK 57 時点でまだ alpha**。「not available in the Expo Go app – use development builds」+ Web 非対応 (Android=Google Maps / iOS=Apple Maps のみ)。破壊的変更が頻繁と公式明記
- **react-native-maps が SDK 57 の公式 pin: 1.27.2** (bundledNativeModules.json。npm latest は 1.29.0 だが `npx expo install` は 1.27.2 を入れる)。Expo Go でそのまま動く (「No additional setup is required when testing your project using Expo Go」)。New Architecture は **1.26.1+ が RN >= 0.81.1** 対応
- **react-native-maps に Web 実装は無い** (peerDeps に react-native-web optional があるだけ)。web shim の @teovilla/react-native-web-maps は 2024-04 で更新停止
- **背景位置は dev build 必須** (iOS/Android とも Expo Go 不可)。expo-location `startLocationUpdatesAsync` + expo-task-manager `defineTask` (top-level scope)。iOS: UIBackgroundModes に location / Android: ACCESS_BACKGROUND_LOCATION + FOREGROUND_SERVICE(_LOCATION)。**前景 watchPositionAsync だけなら Expo Go で足りる**
- RN は WebSocket を標準サポート (追加ライブラリ不要)。再接続 wrapper は reconnecting-websocket が 2022 から未更新で、maintained fork は **partysocket** (1.3.0, 2026-06 更新)
- 状態管理 zustand 5.0.14 は peer react>=18 で React 19.2 OK

## How to apply

- SDK 57 で地図なら react-native-maps@1.27.2 一択 (expo-maps は alpha が取れるまで見送り)
- RN の web ターゲットに地図を出そうとしない。Web は別アプリ (Next.js 等) で maplibre-gl 系を直接使う
- MVP は前景位置で組み、背景共有を入れる段で dev build (EAS) へ移行する
