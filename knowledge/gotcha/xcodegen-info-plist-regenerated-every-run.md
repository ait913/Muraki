---
title: xcodegen の info: は Info.plist を毎回再生成する — 版数を Info.plist に直接書くと消える
category: gotcha
tags: [xcodegen, ios, info-plist, versioning, testflight, cfbundleversion]
created: 2026-07-17
project: global
sources:
  - https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md  # "Plists are created on disk on every generation of the project"
  - https://yonaskolb.github.io/XcodeGen/Docs/ProjectSpec.html
  - https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion
---

## Context

xcodegen で iOS プロジェクトを管理し、`project.yml` の `targets.<T>.info` に `path:` + `properties:` を書いている構成 (atender `apps/ios` が該当)。TestFlight 配布のたびに `CFBundleVersion` をインクリメントする運用。

## What

**`project.yml` に `info:` を書いた時点で、その `path` の Info.plist は「生成物」になる。** ProjectSpec の Plist 節が明言:

> Plists are created on disk on every generation of the project.

つまり `xcodegen generate` を走らせるたびに Info.plist は `properties:` から**上書き再生成**される。

帰結:

- **Info.plist を直接編集して `CFBundleVersion` を上げても、次の `xcodegen generate` で黙って巻き戻る。** エラーは出ない。古いビルド番号のまま archive され、App Store Connect が同一ビルド番号を弾いて初めて気付く
- 版数の唯一の正典は **`project.yml`** 側
- Info.plist を git track していると「生成物が tracked」状態になり、project.yml と二重管理に見える。実際は project.yml が上流で、Info.plist の diff は生成結果に過ぎない

atender では TestFlight 手順書 (`CLAUDE.md`) が「`Atender/Info.plist` の `CFBundleVersion` をインクリメント」と**誤って**指示していた (2026-07-17 発見)。実際の bump commit (`f30391f` / `b96a181` / `3078d66`) は両方を同時に変更しており、手順書どおりにやると壊れるが、実作業では偶然両方触っていたため露見していなかった。

## Why

xcodegen の設計思想は「`project.yml` が単一の正典、`.xcodeproj` も Info.plist も生成物」。`.xcodeproj` を gitignore する発想は浸透しているが、**Info.plist も同じ扱いだという点が見落とされやすい** — Info.plist は人間が手で編集してきた歴史が長く、「設定ファイル」の見た目をしているため。

## How to apply

- `project.yml` に `info:` がある構成では、**版数・Bundle ID・URL scheme 等は必ず `project.yml` 側を編集**する
- 手順書・CLAUDE.md に「Info.plist を編集」と書かない。「`project.yml` の `CFBundleVersion` を上げて `xcodegen generate`」が正
- 生成物である Info.plist を git track するかは選択だが、track するなら「これは生成物」とコメント等で明示し、**編集の入口を project.yml に一本化**する
- 版数の自動化を設計する場合、書き換え対象は Info.plist ではなく `project.yml` (YAML) である。release-please の `extra-files` generic updater 等を当てるならこちら
