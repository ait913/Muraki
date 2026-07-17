---
title: plutil -extract は -o - を省くと入力ファイルを抽出結果で上書きする
category: tool-quirk
tags: [plutil, macos, ios, info-plist, xcodegen, cli]
created: 2026-07-17
project: global
sources:
  - atender feature/ui-revamp-p1 の Reviewer レビュー (2026-07-17) — Info.plist を実際に破壊した
  - man plutil (macOS 15)
---

## Context

iOS の検証で Info.plist の値を確認したくなる場面は多い
(`CFBundleDevelopmentRegion` が `ja` か / `UIAppFonts` に何が登録されているか等)。
`plutil -extract <keypath> <fmt> <file>` は素直な読み取りコマンドに見える。

## What

**`plutil -extract` は `-o` を省略すると、抽出結果を「入力ファイル自身」に書き戻す。**
`-o` の既定値が stdout ではなく **入力ファイル** であるため。

atender で実際に起きたこと:

```sh
plutil -extract CFBundleDevelopmentRegion raw Atender/Info.plist   # 値は表示された
plutil -extract UIAppFonts json Atender/Info.plist                 # ← ここで Info.plist が
                                                                   #   ["GoogleSans-Medium-Latin.ttf"]
                                                                   #   だけの中身に化けた
```

結果、次の `xcodebuild test` が

```
error: unable to read property list from file: .../Atender/Info.plist:
       The operation couldn't be completed. (SWBUtil.PropertyListConversionError error 2.)
```

で **TEST FAILED**。値の表示には成功しているので、壊したことに気付くきっかけが無い。
**「読んだだけ」のつもりのコマンドが破壊的**という点が罠。

## Why

man の記述は `-extract keypath fmt [-o path] [file]` で、`-o` を「alternate path」と呼んでいる。
**alternate の対義語 (既定) は stdout でなく input file**。
`raw` フォーマットは値を stdout にも出すため、「stdout に出た = 読み取りだった」と誤認しやすい。

## How to apply

- **必ず `-o -` を付ける** (`-` = stdout)。これで入力ファイルは無傷:
  ```sh
  plutil -extract CFBundleDevelopmentRegion raw -o - Atender/Info.plist
  plutil -extract UIAppFonts json -o - Atender/Info.plist
  ```
- 壊した後の確認は `plutil -lint <file>`
- **Info.plist は xcodegen の生成物なので `xcodegen generate` で復旧できる**
  (`project.yml` が正典 — `gotcha/xcodegen-info-plist-regenerated-every-run.md`)。
  生成物でない plist を壊すと戻せないので、触る前に `cp` バックアップを取る
- 読むだけなら破壊的でない代替がある: `defaults read <abs-path-without-.plist> <key>` /
  `/usr/libexec/PlistBuddy -c "Print :UIAppFonts" <file>` / 単に `grep -A4 UIAppFonts <file>` (XML plist なら十分)
- **一般則**: 「読み取り」に見える CLI が破壊的でないことを、書き込み先の既定値を確認せずに仮定しない。
  Reviewer の負のコントロールでは、対象を触る前に必ずバックアップを取る作法がここでも効く
