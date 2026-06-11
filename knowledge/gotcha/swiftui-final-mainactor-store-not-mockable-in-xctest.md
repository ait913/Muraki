---
title: SwiftUI の final class + @MainActor な Store/ViewModel は XCTest でサブクラスモックできない
category: gotcha
project: global
tags: [swift, swiftui, xctest, mocking, mainactor, di]
created: 2026-06-08
sources:
  - Muraki/projects/atender/.designs/20260608-ios-foundation.md (§9.1)
  - atender iOS Phase iOS-1 reviewer 検証
---

## Context

SwiftUI + Observation で `@Observable @MainActor final class AuthStore`/`ViewModel` を作り、設計doc に「テスト時は Keychain / APIClient をプロトコル化してモック注入」と書いた。だが Store 自体が `final` だとサブクラス差し替えができず、`@MainActor` だとテストコードも `@MainActor` 必須になる。

## What

- `final class` は**サブクラスモックを作れない**。「○○Store をモックする」前提のテストは破綻する。設計時に、モックしたいのは「Store 本体」か「Store が依存する protocol(KeychainStoring / APIClient)」かを決める。
- 実務的な対処:
  - **依存を protocol 化**して Store の init に注入(`AuthStore(keychain: KeychainStoring, session: URLSession)`)。Store 本体は final のまま、依存だけ差し替える。
  - HTTP は `URLProtocol` スタブで `URLSession` ごと差し替える(Store/APIClient を触らず実体経由で検証できる)。
  - Store 本体の挙動は「実体を動かして observable state(`state == .signedOut` 等)を assert」で間接検証。`handleUnauthorized()` が呼ばれたか等も state で見る。
- `@MainActor` の型をテストする XCTest クラス/メソッドは `@MainActor` を付ける(または `await MainActor.run`)。付け忘れると `main actor-isolated ... can not be referenced` でコンパイル不能。
- init シグネチャ(依存注入の口)は**設計doc に明記**する。書かないと Reviewer がテストを書けず、コンパイラ逆引きで実装に寄る([[gotcha/design-doc-must-specify-swift-type-signatures]])。

## How to apply

- 設計段階で「テスト対象の Store/ViewModel の public init(注入する protocol)」を決めて doc に書く。
- HTTP 層は URLProtocol スタブを既定の手段にする(最も移植性が高い)。
- Keychain 等の副作用境界は protocol(`KeychainStoring`)で切る。
- Reviewer のテストクラスは `@MainActor`、async は `await`。
