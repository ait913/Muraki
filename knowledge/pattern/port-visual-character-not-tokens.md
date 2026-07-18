---
title: 別プラットフォームの視覚品質を移植する — 値でなく「性格」を写す
category: pattern
tags: [ui, design-language, cross-platform, ios, web, design-tokens, visual-character]
created: 2026-07-18
project: atender
sources:
  - Muraki/projects/atender/DESIGN.md
  - Muraki/projects/atender/apps/web/src/styles.css
  - Muraki/projects/atender/apps/web/src/components/event-tile/EventTile.tsx
---

## Context

atender は Web 版が「丸めでポップで綺麗」なのに iOS ネイティブ版が「詰め詰めで10年前」になった。原因を「Web トークンを iOS に 1:1 移植していないから」と誤診しやすいが、実際は逆だった。iOS の DESIGN.md (視覚言語の正典) を書く過程で得た、クロスプラットフォームで視覚品質を揃えるときの設計判断。

## What

**移植すべきは「性格 (visual character)」であって「トークンの値」ではない。**

- 「性格」= 丸み / 余白 / 密度 / 奥行き (影) / 情報の配置 (上寄せ vs 中央) / 面と線のどちらが主役か。これはプラットフォーム非依存で写せる。
- 「値」= 色の hex、px 単位、フォント名。これは各プラットフォームの中立語彙 (iOS の system semantic color / built-in text style) に明け渡すべきで、1:1 移植すると標準部品・OS の質感表現 (Liquid Glass 等) と干渉する。

**さらに核心**: トークンの**値が既に一致していても**「10年前」は起きる。atender の iOS は `Radius`/`Shadow`/`Color` を Web と 1:1 で持っていたのに、**適用の仕方**が違った:
- セル背景を透過で描く (Web は不透明 tint) → 下地の罫線が透ける
- グリッド線を濃い罫線で描く (Web は 8% hairline or 1px gap) → 表組みに見える
- テキスト中央寄せ (Web は上寄せ) → 情報密度が落ちる
- 見出しスケールが画面ごとにバラバラ (Web は横断で統一)

→ 問題は「値」でなく「適用規則」。DESIGN.md の仕事は新トークンの発明でなく**既存トークンの適用規則を固定する**こと。

## Why

- 中立要素 (色/書体/罫線) を pt に 1:1 移植すると、システムの奥行き 2 セット (base/elevated) や Dynamic Type、Liquid Glass を壊す (HIG)。だから値は明け渡す。
- 一方、丸み・余白・配置は「正しい (HIG 準拠)」だけでは決まらない品質軸で、放置すると「HIG 準拠だが安っぽい」に着地する。ここを正典側の実装 (綺麗な方) から**性格として**移植すると「良い」が作れる。
- 値が一致していても壊れるのは、視覚品質が「トークンの存在」でなく「トークンの適用箇所と適用方法」で決まるから。トークンは必要条件で十分条件ではない。

## How to apply

- 「A を B に移植して」型の UI 要望では、まず**何を契約とするか**を分ける: 値の移植 (色 hex 等) / 性格の移植 (丸み・余白・配置) / 中立の明け渡し (system semantic へ)。
- 正典側 (品質が高い方) の**描画ロジックを読む** (CSS/コンポーネント)。「不透明 tint か透過か」「テキストは上か中央か」「線が主役か面が主役か」を実測で言語化する。スクショの印象論で終えない。
- 移植先のトークンが既に同値かを先に確認する。同値なら DESIGN.md は「新トークン」でなく「適用規則の表」を書く (役割 → トークン → 値 → 適用対象)。
- Touri の個別不満 (「透過が気になる」「詰め詰め」) は**その場の修正でなく再発しない原則**に変換し、原則→不満のトレーサビリティ表を DESIGN.md に持たせる (Developer が原則だけで全不満を説明できるか検証可能にする)。
- グリッド/カレンダーの「10年前」感は、たいてい**セル個別の table border** が主因。枠を廃し「白い丸カード + gap 分離 + 不透明 tint chip」に置換するのが最大のレバー。
</content>
