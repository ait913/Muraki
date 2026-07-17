---
title: Font.custom の無言フォールバックが UIAppFonts 登録漏れを隠す (検証は UIFont(name:) で)
category: gotcha
project: atender
tags: [ios, swiftui, font, uiappfonts, xctest, negative-control]
created: 2026-07-16
sources:
  - projects/atender/.designs/20260716-ios-phase-e-settings-setup-gcal.md (E0-5)
  - atender feature/phase-e-p1 Reviewer 実測 (2026-07-16)
---

## Context

atender iOS は Inter 5 種 + NotoSansJP をバンドルし `Typography.swift` が `Font.custom("Inter-Medium", …)` を呼んでいた。
フォントファイルは `.app` にコピーされていたが `Info.plist` の **`UIAppFonts` が存在しなかった**。
結果、**アプリ全体が Inter でなく SF Pro で描画されたまま TestFlight に出ていた**。誰も気付かなかった。

## What

- **`Font.custom(_:size:)` (SwiftUI) は名前解決に失敗しても黙ってシステムフォントにフォールバックする。** エラーも警告も出ない。
  → **バグが「動いているように見える」ので、目視でもテストでも検出されない。**
- **`UIFont(name:size:)` (UIKit) は解決失敗で `nil` を返す。** 登録の真偽判定に使えるのはこちら。
- バンドルにファイルがあるだけでは登録されない。`UIAppFonts` に**バンドル内のファイル名**を書いて初めて登録される。
  `UIAppFonts` に書くのは**ファイル名** (`Inter-Bold.ttf`)、`Font.custom`/`UIFont(name:)` が要求するのは
  **PostScript 名 (name テーブル nameID 6)**。両者は一致する保証がない → **実測すること**。
- **可変フォントの罠**: NotoSansJP の可変フォントは PostScript 名が `NotoSansJP-Thin` のみ (wght default=100)。
  fvar の named instance (Thin〜Black) は psNameID を持たないため **`NotoSansJP-Regular` は nil が正解**。
  名前で参照すると日本語がヘアラインで描画される。登録しても**自動で日本語にカスケードはしない**
  (「登録した = 日本語が Noto Sans JP になる」ではない)。

## Why

`Font.custom` の設計はフォント欠落時もクラッシュさせない親切設計だが、その親切さが**恒久的な無言バグ**を作る。
「見た目が出ている」ことは「意図した書体で出ている」ことを何も保証しない。
同じ構造は「フォールバックが親切な API」全般 (画像プレースホルダ、ロケール既定など) に共通する。

## How to apply

**テストは `UIFont(name:)` で書く。`Font.custom` を検証に使わない。**

```swift
// 負の対照を必ず先に置く (assert に牙があること = vacuous pass でないことの証明)
XCTAssertNil(UIFont(name: "ThisFontIsNotRegistered-XYZ", size: 14))

XCTAssertNotNil(UIFont(name: "Inter-Bold", size: 14))
XCTAssertEqual(UIFont(name: "Inter-Bold", size: 14)?.fontName, "Inter-Bold")  // 別フォントに化けていない

// ★ 最重要: プロダクトコードが実際に使う名前生成関数と登録の結合テスト。
//   「Typography が要求する名前」と「実際に登録された名前」の不一致を機械的に検出する。
for w in [Font.Weight.regular, .medium, .semibold, .bold, .black, .heavy] {
    XCTAssertNotNil(UIFont(name: Font.interPostScriptName(for: w), size: 14), "\(w) の PostScript 名が未登録")
}
```

- 名前定数をテストに**ベタ書きするだけでは不十分**。プロダクトの名前生成関数を**呼んで**登録と突き合わせる
  (ベタ書きだけだと Typography 側が別名を使い始めても検出できない)。
- PostScript 名は推測せず `name` テーブル (nameID 6) を直接パースして実測する。
- **negative control が安い**: 修正前の `project.yml` を `git show <base>:apps/ios/project.yml` で当てて
  `xcodegen generate` → テストが赤くなることを確認する。これで「GREEN は修正が作った」と言い切れる
  (atender P1 で実施 — Inter 5 種すべて nil に落ちることを確認)。
- xcodegen 構成では `Info.plist` を直接編集しない。`project.yml` の `targets.<T>.info.properties` が正典。
- **書体変更は横断的変更**。ユニットテストは「登録された」しか言わない。Inter は SF Pro とメトリクスが違うため
  clipping / 折り返し / truncation が起きる。レイアウト崩れは別途スクショ回帰で見る。
