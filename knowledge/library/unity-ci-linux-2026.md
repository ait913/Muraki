---
title: Unity CI ビルド (Linux/GameCI) の 2026-10 時点の事実
category: library
project: cross
tags: [unity, gameci, ci, linux, license, wasawasa]
created: 2026-10-14
sources:
  - https://docs.unity3d.com/6000.0/Documentation/Manual/ManualActivationCmdWin.html
  - https://docs.unity3d.com/6000.0/Documentation/Manual/system-requirements.html
  - https://github.com/game-ci/documentation (docs/03-github/02-activation.mdx, 04-builder.mdx, 06-deployment/ios.mdx, 08-docker/01-docker-images.mdx)
  - https://github.com/game-ci/unity-builder/releases
  - https://unity.com/en/products/pricing-updates
---

## Context
wasawasa に Unity ビルドを載せる前調査 (2026-10-14)。

## What
- Unity Editor の Linux サポートは Ubuntu 22.04 / 24.04 (x64)。推奨 RAM 8GB 以上 (Unity 6 system requirements)。
- GameCI: `unityci/editor` (game-ci/docker)。unity-builder は 2026-09 に v5.0.1 / v6.0.0 (game-ci/cli への薄いラッパ、入力は v5 互換)。Unity 6.6+ は /dev/shm 1GiB を要求し `--shm-size=1025m` 必須 (builder 5.0.1 以降は既定で渡す、`dockerShmSize` 入力)。
- ターゲット例 (builder docs): StandaloneLinux64 / Windows / WebGL / Android / iOS を ubuntu で。StandaloneOSX の IL2CPP は Linux イメージ不可。
- iOS: Linux で出るのは Xcode プロジェクトまで。署名・ipa 化は Mac の Xcode 必須 (GameCI iOS デプロイ docs)。
- ライセンス: Personal は Unity Hub で .ulf を作り (Linux: ~/.local/share/unity3d/Unity/Unity_lic.ulf) UNITY_LICENSE/EMAIL/PASSWORD を渡す。Pro/Plus は UNITY_SERIAL。floating は license server URL。Unity 公式: 手動 (.alf) アクティベーションは Personal 非対応、`-serial` は有償のみ。Personal の CI 活性化は GameCI 方式 (.ulf 流用) で、Unity 公式の保証経路ではない (GameCI 側にも Personal 破損 issue あり)。
- Unity Build Automation: 2026-03-01 から無料枠に Mac ビルド 100 分/月 (iOS 可)。有償枠の分数は未確認。
- Coolify 4.4.6 の API: scheduled-tasks は cron で既存アプリコンテナ内実行。オンデマンドの one-shot 実行 API は routes/api.php に無い。

## Why
設計前提の確認用。

## How to apply
ライセンス運用 (Personal の .ulf はアカウント紐付けで期限・失効あり得る) と iOS の Mac 要件を最初に設計へ入れる。
