---
title: 非 Optional な DTO フィールド追加は wire では additive でも呼出し側には source-breaking
category: gotcha
tags: [swift, typescript, zod, dto, additive, memberwise-init, xctest, codex-sandbox]
created: 2026-07-21
project: atender
sources: [".designs/20260721-public-timetable-search.md", "sessions/2026-07-21"]
---

## Context
atender「公開時間割検索」で、shared zod と iOS の `TemplateDto` に **非 Optional** な
`schoolName`/`departmentName` を足した。設計 doc は「additive のみ・Web を壊さない」と正しく
書いていたが、これは **wire 契約 (JSON payload)** の話。実装コード/テストコードのレベルでは
additive ではなかった。

## What
non-optional フィールドの追加が壊したもの (backend は無傷、iOS で 2 件):

1. **memberwise init の全呼出し** — Swift の struct は memberwise init が全 stored property を
   要求する。`TemplateDto(id:..., updatedAt:...)` と書いていた既存箇所 (本番/テスト問わず) が
   引数不足で**コンパイルエラー**。atender では `RoomLogicTests.swift` の 1 箇所で
   AtenderTests target 全体がビルド不能になり、268 GREEN ベースラインが崩れた。
2. **共有 decode fixture** — 非 Optional なので、新フィールドを欠く既存 fixture (`template.json`)
   の decode が**実行時 throw**。それを success 前提で使う既存テストが赤くなる。

**気づかれなかった理由が重要**: Developer (Codex) の sandbox は GoogleSignIn の SwiftPM clone が
ネットワーク制限で落ちるため **iOS test target を一度もコンパイルできない**。コンパイル破綻が
無検出のまま commit された。

## Why
- wire の additive (zod 非 strict / 常に出力) と、言語レベルの source compatibility は別問題。
- Swift memberwise init・Codable 合成 init・decode fixture はいずれも「全 non-optional が存在する」
  ことを前提にするので、1 フィールド追加が既存の全呼出し点に波及する。
- TypeScript/zod 側は object literal を作る箇所が少なく波及が小さいが、Swift は memberwise init を
  多用するため波及が大きい。

## How to apply
- **Architect**: iOS DTO に非 Optional を足す設計では、触るファイル一覧に「**その DTO の
  memberwise init 呼出し箇所**」と「**decode fixture**」を明示的に含める。B6 型の「欠落で throw」
  テストは既存 fixture を更新すると成立しなくなるので、**別 inline JSON を使う**と設計に書く。
  迷ったら Optional + default を検討 (ただし nil 分岐が増えるトレードオフ)。
- **Developer**: iOS の struct にフィールドを足したら、sandbox で iOS test target がビルドできなく
  ても「未検証」と明示的に上申する (「実装した」で止めない)。memberwise init 呼出しの
  grep (`grep -rn "TemplateDto(" apps/ios`) だけは sandbox でもできる。
- **Reviewer**: 非 Optional 追加 feature は必ず sandbox 外で `xcodebuild build-for-testing` を回す。
  pass/fail 以前に**コンパイルが通るか**が第一関門。`grep -nE "error:" build.log | grep -v "0 errors"`。
