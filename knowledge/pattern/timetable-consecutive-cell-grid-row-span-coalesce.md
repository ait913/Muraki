---
title: 時間割の連続コマは「描画前 coalesce + CSS Grid grid-row span」で結合
category: pattern
project: global
tags: [timetable, css-grid, grid-row-span, react, rendering]
created: 2026-06-02
sources:
  - Muraki/projects/atender/.designs/20260602-ui-improvements.md (項目1)
  - apps/web/src/lib/coalesceTimetableEvents.ts, components/timetable/TimetableView.tsx (atender)
---

## Context

時間割グリッドで、同一授業が連続コマ (例 月1限+2限) にまたがるとき 1 つの縦長ブロックとして表示したい。データ上は隣接コマが別レコード (各 periodCount=1) に割れていることがある (後付け追加・テンプレ取込・週ビューの slot 照合変換)。

## What

2 段で対処する:

1. **描画前に pure 関数で隣接コマを coalesce**:
   - `mergeKey` (同一性キー。例 courseId / userId:courseId) を各 event に持たせる。
   - `(dayOfWeek, mergeKey)` でグルーピング → startPeriodIndex 昇順 → 「次の startPeriodIndex == 現ブロックの startPeriodIndex+periodCount」なら吸収して periodCount 加算。
   - mergeKey 未指定は素通し。結合後 id は先頭 event の id を温存 (クリック時の find 整合)。
2. **CSS Grid の `grid-row: <n> / span <span>` でブロックをグリッド直下の子として配置**:
   - イベントは `gridColumn` / `gridRow: <start> / span <span>` で N 行ぶち抜き。
   - **重要**: 同一グリッド内で背景セル (角・ヘッダ・限目ラベル・空セル) も**全て明示の gridColumn/gridRow を付ける**。イベントだけ明示配置にして背景を自動配置にすると、CSS Grid が明示配置を先に埋め自動配置を残り空きに流すため背景セルがズレて崩れる ([[gotcha/css-grid-mixed-explicit-auto-placement-collision]])。
   - **やってはいけない**: 個別セル div を `overflow-hidden` にして、その中で `height: calc(span*100%+...)` の絶対配置タイルを伸ばす方式。→ セル境界でクリップされ縦に伸びない (atender で実際に踏んだバグ)。
   - 占有セル集合 (`occupiedSet`) を作り、イベントが乗るセルには空セル (追加ボタン) を描画しない。
   - 同一開始セルに複数ブロック (mergeKey 違い) → 同じ gridColumn/gridRow の 1 ラッパーに入れて `flex` で横並び (span はブロック群の最大 span)。

## Why

- `grid-row: span N` はブラウザネイティブで行高 (`1fr`) に依存せず堅牢。絶対配置 + calc 方式は親の overflow とグリッド行高に依存して脆く、side-by-side との両立も複雑。
- 描画側 coalesce にすることで、API/DB を変えず既存データ (割れたレコード) も救済できる。

## How to apply

- 共用コンポーネント (自分用 / ルーム用で同じ TimetableView を使う等) では coalesce を**コンポーネント内部で 1 回**実行し、呼び出し側は raw events + mergeKey を渡すだけにする (二重 coalesce や画面ごとの破綻を防ぐ)。
- テスト: coalesce は pure で隣接結合/非隣接据置/曜日違い/mergeKey違い/undefined素通し/id温存/ソートを unit。描画は jsdom で `style` 生文字列が `grid-row` に `span N` を含むこと・継続行に空セルが出ないこと・結合タイルが 1 つに集約されることを構造 assert (getComputedStyle/calc は jsdom で評価不可)。
- 描画テストを Reviewer に書かせるなら、対象の**公開 prop 契約**を設計doc に明記すること: [[gotcha/design-must-specify-component-prop-contract-for-render-tests]]
- 関連: [[pattern/single-screen-compressed-timetable]] [[pattern/grid-table-borders-bp]]
