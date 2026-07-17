---
title: 日本語 UI なのに「英語アプリ」として出荷される (system の Back が "Back" になる)
category: gotcha
tags: [ios, xcodegen, localization, uikit, swiftui, navigation, info-plist]
created: 2026-07-17
project: global
sources:
  - atender iOS UI 刷新の設計 (2026-07-17) — Architect がシミュレータで実測 + 負の対照
  - projects/atender/.designs/20260717-ios-ui-revamp.md (F1/F2)
---

## Context

atender iOS は UI 文字列が**全部ベタ書きの日本語**で、`.lproj` を 1 つも持たない。
それでも system の戻るボタンが英語の "Back" になるため、**わざわざ `BackHeaderButton` という自前部品を作り、
全画面で `.toolbar(.hidden, for: .navigationBar)` して nav bar ごと隠していた。**

nav bar を隠す = Liquid Glass の nav bar も scroll edge effect も large title も捨てる、という
連鎖的な損失が発生していた。原因は config 1 行。

## What

- **バンドルの言語は `CFBundleDevelopmentRegion` で決まり、既定は `en`。** UI 文字列が何語でも関係ない
- iOS は「ユーザーの優先言語 ∩ アプリの対応ローカライズ」でアプリの実行言語を決める。
  アプリが `en` しか名乗らなければ、**日本語端末でも UIKit の system 文字列は英語**になる
- **`.lproj` は 1 つも要らない。** development language を `ja` にするだけで:

  ```
  Bundle.main.localizations            == ["ja"]
  Bundle.main.preferredLocalizations   == ["ja"]
  Bundle.main.developmentLocalization  == "ja"
  Bundle(for: UIViewController.self).localizedString(forKey: "Back", value: "?", table: nil) == "戻る"
  ```

- **XcodeGen での直し方** (`project.yml`):

  ```yaml
  options:
    developmentLanguage: ja      # → pbxproj の developmentRegion = ja / knownRegions = (Base, ja)
                                 # → build setting DEVELOPMENT_LANGUAGE = ja
  ```

  生成される Info.plist は `CFBundleDevelopmentRegion = $(DEVELOPMENT_LANGUAGE)` なので `ja` に解決される。
  **`Info.plist` を手編集しても xcodegen が毎回巻き戻す** (`gotcha/xcodegen-info-plist-regenerated-every-run.md`)。正典は `project.yml`

## Why

`Font.custom` の無言フォールバックと同じ構造 — **「日本語が表示できている」ことは「日本語アプリとして動いている」ことを何も保証しない。**
アプリ自身が描く文字列は当然日本語で出る (ベタ書きだから)。英語で出るのは**フレームワークが描く文字列だけ**
(back / Cancel / Done / 編集メニュー / アクセシビリティ読み上げ / 日付ピッカー…)。

だから症状は「system の部品だけ英語」という**部分的な違和感**として現れ、
「iOS の戻るボタンは英語なんだな」と誤解して**自前部品で回避する**方向に進みやすい。
実際 atender は 9 ヶ月それで走り、自前 back + nav bar 全隠しという構造的な負債になった。

## How to apply

- **日本語アプリを作ったら最初に `developmentLanguage: ja` を設定する。** `.lproj` を作る話とは別物
- **「system の部品だけ英語」を見たら自前で作り直す前にここを疑う。** 自前 back / 自前ツールバーは
  ほぼ確実にこの誤診の産物
- テストで固定できる (assert に牙がある):

  ```swift
  XCTAssertEqual(Bundle.main.preferredLocalizations, ["ja"])
  XCTAssertEqual(Bundle(for: UIViewController.self).localizedString(forKey: "Back", value: "?", table: nil), "戻る")
  ```

- **負の対照が安い**: `project.yml` から `developmentLanguage` を外して `xcodegen generate` → 上の assert が
  `["en"]` / `"Back"` になることを確認してから戻す。これで「GREEN は修正が作った」と言い切れる
  (atender で実施済 — 1 ビルドで済む)
- **副作用**: アプリの対応ローカライズが `ja` だけになるので、英語端末のユーザーにも system 文字列が
  日本語で出る。日本語専用アプリなら意図どおり。多言語化するなら `.lproj` を足す話に移る
