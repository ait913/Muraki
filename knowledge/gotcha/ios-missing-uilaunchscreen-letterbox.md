---
title: iOS Info.plist に UILaunchScreen が無いとレターボックス(上下黒帯)描画になる
category: gotcha
project: atender
tags: [ios, swiftui, xcodegen, info-plist, launch-screen]
created: 2026-07-09
sources:
  - atender apps/ios (2026-07-09 セッション)
---

## Context

atender iOS を実機/シミュレータで起動すると、画面上下に黒帯が出て「小型デバイス(SE)相当に縮小描画」されているように見えた。時間割グリッドが途中で切れ、safe-area も狂ってタブバー下の余白が不揃いだった。

## What

`Info.plist` に **`UILaunchScreen` キーが無い**と、iOS はそのアプリを「旧世代デバイス向け」と判断し、**互換モード(レターボックス)で描画**する。結果、フル解像度を使わず上下に黒帯が入り、safe-area インセットも実機と異なる誤った値になる。

`xcodegen` 運用では `Info.plist` は生成物なので、**plist を直接編集しても次の generate で消える**。`project.yml` の `targets.<T>.info.properties` に追加するのが正。

```yaml
info:
  path: Atender/Info.plist
  properties:
    UILaunchScreen: {}   # ← 空 dict で「フルスクリーン対応・空のランチスクリーン」を宣言
```

生成後 `Info.plist` に `<key>UILaunchScreen</key><dict/>` が入り、互換モードが解除されてフル高描画になる。

## Why

`UILaunchScreen`(iOS 14+ の launch storyboard 後継)が無い＝「モダンな画面サイズに対応していない」と OS が解釈するため。空 dict でも「対応済み」の宣言として十分。

## How to apply

- 黒帯・縮小描画・safe-area 崩れを見たら、まず `Info.plist` の `UILaunchScreen` 有無を疑う
- xcodegen プロジェクトでは `project.yml` の `info.properties` に `UILaunchScreen: {}` を追加 → `xcodegen generate`
- この1修正が**全画面にグローバルに効く**(個別画面の余白調整より先にやる)
- 関連: safe-area が正しくなるとフローティングタブバー下の余白ズレも連動して直る
