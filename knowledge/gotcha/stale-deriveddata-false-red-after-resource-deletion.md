---
title: バンドル資源を削除した後の xcodebuild は古い DerivedData で偽の RED を出す (実装は無罪)
category: gotcha
project: cross
tags: [ios, xcodebuild, deriveddata, xcodegen, fonts, uiappfonts, false-negative, verification]
created: 2026-07-17
sources:
  - "session 2026-07-17-24e295f6 (atender UI 刷新 P1。Leader が Reviewer の GREEN を独立検証したら 1 RED が出て、危うく Developer に差し戻すところだった)"
---

## Context

atender の UI 刷新 P1 で、バンドル済フォント (`Inter-*.ttf` 5 本 + `NotoSansJP`) を**削除**し、`project.yml` の `UIAppFonts` を 7 件 → 1 件に減らした。Reviewer は **263 GREEN / 0 RED** を報告。Leader が独立検証で同じコマンドを回したら:

```
Executed 263 tests, with 25 tests skipped and 1 failure
TypographyRegistrationTests.testGoogleSansRemainsRegistered:
  XCTAssertNotNil failed - GoogleSans-Medium が未登録
** TEST FAILED **
```

**Reviewer の報告を疑う材料に見えた**が、実装は無罪だった。

## What

**共有 DerivedData を使った増分ビルドは、バンドル資源の削除を正しく反映しないことがある。** 結果、フォント登録 (`UIAppFonts`) の状態が古いまま実行され、`UIFont(name:)` が nil を返す = **偽の RED**。

紛らわしいのは、**静的な検査は全て「正しい」と答える**こと:

| 調べたもの | 結果 |
|---|---|
| `Resources/Fonts/GoogleSans-Medium-Latin.ttf` の実在 | ✅ ある |
| フォントの PostScript 名 (`name` テーブル nameID 6) | ✅ `GoogleSans-Medium` = テストが引く名前と一致 |
| `project.yml` の `UIAppFonts` | ✅ ファイル名が一致 |
| **生成された `Info.plist` の `UIAppFonts`** | ✅ 正しい |
| **`.app` バンドル内の `.ttf`** | ✅ 入っている |
| **`.app` 内 `Info.plist` の `UIAppFonts`** | ✅ 正しい |

**それでも実行時に nil。** 成果物を静的に見ても原因に辿り着けない。

**隔離した DerivedData で同じコマンドを回すと即座に GREEN**:

```
testGoogleSansRemainsRegistered ... passed
Executed 263 tests, with 0 failures
** TEST SUCCEEDED **
```

**副次的な徴候: `25 tests skipped`。** 偽 RED の run にだけ現れ、クリーン run では 0。**skip 数が突然増えたら DerivedData を疑う** (テストの中身は何も変わっていないのに skip されるのは、そもそもビルド状態がおかしい徴候)。

## Why

`xcodegen generate` は `.xcodeproj` を**毎回作り直す**。プロジェクトファイルの同一性が変わるため、増分ビルドの依存解決が古い成果物を再利用してしまう場合がある。特に**削除**は「作られなかったファイル」として現れるので、増分ビルドが「変更なし」と判断しやすい。

`UIAppFonts` の登録はアプリ**プロセス起動時**に走る。シミュレータにインストール済のアプリが古い登録状態を持っていると、`.app` の中身を静的に見ても実行時の挙動と一致しない。**「成果物が正しい」と「実行時の状態が正しい」は別**。

## How to apply

**バンドル資源 (フォント / アセット / Info.plist のキー) を削除・変更した後の検証は、必ず隔離した DerivedData で行う。**

```sh
xcodebuild test -project X.xcodeproj -scheme X \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2' \
  -derivedDataPath /path/to/scratchpad/dd-clean
```

`-derivedDataPath` は既存の `~/Library/Developer/Xcode/DerivedData` を**一切壊さない**ので、`rm -rf` より安全 (かつ permission gate にも弾かれない)。

**判定の作法** — GREEN/RED が Reviewer と Leader で割れたら、**割れた事実を「相手が間違い」と読まない**。同じコマンドでも DerivedData の状態が違えば結果は変わる。**先に環境を揃えてから比べる**。今回 Leader は静的検査を 6 つ通して全部 ✅ だったのに RED が出た時点で「実装以外の何か」に舵を切るべきだった。

**「実装が悪い」と結論する前に必ず通す関門**:
1. 隔離 DerivedData で再現するか → しなければ環境
2. `skip` 数が想定外に増えていないか → 増えていれば環境
3. 静的検査 (成果物の中身) が全部通るのに実行時だけ落ちる → **ほぼ環境**

関連: [[gotcha/xcodegen-info-plist-regenerated-every-run]] (xcodegen が Info.plist を毎回作り直す)、[[gotcha/icloud-synced-venv-git-stall]] (環境要因をコード欠陥と誤認しないための切り分け)
