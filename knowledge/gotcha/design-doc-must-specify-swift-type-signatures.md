---
title: 型付き言語(Swift等)では設計docに「挙動」だけでなく型/シグネチャを書かないとReviewerが実装に寄る
category: gotcha
project: global
tags: [swift, design-doc, reviewer, test-independence, codable]
created: 2026-06-08
sources:
  - Muraki/projects/atender/.designs/20260608-ios-foundation.md (§4, §7)
  - atender iOS Phase iOS-1 reviewer 検証
---

## Context

Web(TS/RTL)では「挙動仕様(○○のとき△△)」だけで Reviewer がテストを書け、実装を見ずに独立検証できた。だが Swift のような静的型 + コンパイル必須の言語で iOS テストを書かせたら、設計に**型・メソッドシグネチャが無い**ため Reviewer がコンパイルできず、結局コンパイラの型エラーを逆引きして実装に寄せた。検証の独立性が崩れる。

## What

型付き言語の設計doc では、挙動仕様に加えて**テスト対象の公開インターフェースを明記**する。最低限:

- **DTO の Optional 性**: 各フィールドが `T` か `T?` か(Zod の `.nullable()`/`.optional()` を Swift Optional に畳む際、どれが Optional かを表に書く)。
- **enum の存在と rawValue**: 文字列 enum を別型にするなら型名(例 `AttendanceDayStatus`)も列挙。`AttendanceStatus` だけ書いて `AttendanceDayStatus` を落とすと Reviewer が String と誤認する。
- **ViewModel / Store の public API**: `init(...)`(注入する依存)・公開 `var`・`func` の正確なシグネチャ(例 `func mark(_ occurrence: OccurrenceDto, status:)` なのか `mark(occurrenceId: String, ...)` なのか)。挙動だけだと書けない。
- **エラー型のケース**と判定方法。

## Why

Web の動的検証(RTL は実行時に DOM を見る)と違い、Swift テストは**コンパイル段階で型が合わないと走らない**。型が doc に無ければ Reviewer は (a) 推測で書いて落ちる、(b) 実装を読んで合わせる(独立性喪失)の二択になる。後者は「実装に寄ったテスト」になり検証価値が下がる。

## How to apply

- Architect は型付き言語の設計で、§データモデルに **DTO フィールドの Optional 性一覧** と **enum 型名**、§各画面に **ViewModel public API(init/var/func)** を明記する。
- それでも漏れたら、Reviewer は「どのシグネチャが設計に無かったか」を報告し、次フェーズで Architect が doc を補う(実装に寄せた事実を隠さない)。
- 関連: [[gotcha/swiftui-final-mainactor-store-not-mockable-in-xctest]] [[gotcha/design-must-specify-component-prop-contract-for-render-tests]]
