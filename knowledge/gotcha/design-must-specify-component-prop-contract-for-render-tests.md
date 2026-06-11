---
title: 描画テストを起こすなら設計docにコンポーネントの prop 契約を明記させる
category: gotcha
tags: [reviewer, testing, design-doc, react-testing-library, props]
created: 2026-06-02
project: atender
sources: [".designs/20260602-ui-improvements.md 項目1 TimetableView", "kinketsu-taisaku .designs/20260608-ui-cloudflare-redesign.md §6.1/§10 MonthView empty-records"]
---

## Context
atender UI改善 項目1。設計docの「挙動仕様」が TimetableView の描画結果
(grid-row に span 2 / 継続セルに空セル非表示 / 隣接 meeting が 1 タイルに結合 等)
を詳細に規定していた。Reviewer はこれを根拠に RTL 描画テストを生成した。

## What
テストが全件 fail。原因は assertion ではなく「コンポーネントに渡す props の形が
doc から確定できない」こと:
- `TimetableEventInput` の表示テキストを持つフィールド名 (`title`? `courseName`? `subtitle`?)
  が doc に列挙されていない。coalesce 仕様で `title/color/subtitle` を head から引き継ぐとは
  書かれているが、EventTile に渡る表示フィールドの確定情報がない。
- `days` prop の形 (`{dayOfWeek,label}[]`? 数値配列?) が未定義。
- 空セルクリックの affordance (button の accessible name "+"? onClick の引数が
  `(dayOfWeek, periodIndex)` か `(dayObject, periodIndex)` か) が未定義。
実際 onEmptyCellClick は doc 記載の `(1,1)` でなく `({dayOfWeek,label}, 1)` で呼ばれており、
events を `title` フィールドで渡しても EventTile の表示テキストが空のままだった
(events が描画されないのか field 名違いなのか、src を読めない Reviewer には切り分け不能)。

## Why
描画の「結果」だけ規定して「入力 (props) の契約」を規定しないと、Reviewer は
prop の形を推測するしかなく、推測が外れると「実装バグ」か「テストの prop ミス」か
を区別できない。これは pure 関数 (coalesce/expand/resolveTheme は doc にシグネチャと
フィールドが明記されていて全 GREEN) との決定的な差。コンポーネントは型が src 側にあり、
doc に転記されないと Reviewer から見えない。

## How to apply
- Architect: 描画テストを Reviewer に書かせる項目は、対象コンポーネントの
  **公開 props の型 (フィールド名・形・コールバック引数順)** を設計docに転記する。
  特に「テスト根拠」と書いた挙動が依存する prop は省略しない。
  既存型を流用する場合も「`TimetableEventInput = {id,title,color,dayOfWeek,
  startPeriodIndex,periodCount,mergeKey?}` (既存)」のように doc に列挙する。
- コールバックの引数 (順序・型) も明記。`onEmptyCellClick(dayOfWeek:number, periodIndex:number)`
  のように。doc に `onEmptyCellClick(1,1)` とだけ書くと第1引数の型が曖昧。
- アクセシブルな affordance (空セルの button name 等) も assert 根拠なら明記。
- Reviewer: 描画テストが「要素が見つからない」で全 fail し、pure 関数側は通る場合、
  まず prop 契約が doc に無いことを疑い、src を読んで合わせにいかず YELLOW で
  「doc に prop 契約が無くテスト不能」と報告する (実装に合わせると検証機能が死ぬ)。

## 追補: query で駆動する View コンポーネントは「query data shape」も同じ責務 (kinketsu-taisaku 2026-06-08)

CF風 UI 再設計の Reviewer 検証で同根の問題が再発。`empty-records` (records 0 件で空状態) を
RTL で検証しようと MonthView を render したが、`useQuery` を queryKey 別にモックしても
`MonthView.tsx:94` が `undefined.incomeForecast` で落ち続けた。設計 doc には:
- §2 に query key 一覧 (`["month"]` `["forecast"]` 等) はある
- §8.1 に summary 値 (currentBalance / endingBalanceForecast) の data-testid 不変条件はある

が、**各 query が返す data の shape** と **MonthView がどの query のどのフィールドを
どう派生して読むか** が無い。`incomeForecast` を month data 直下に入れても forecast に入れても
落ちる = 実装は別の派生 (useMemo / 別 query 要素) から読んでおり、src を読まない Reviewer
には mock 契約が一意に決まらない。prop 契約と全く同じ構造の欠落で、対象が props でなく
**TanStack Query の data 契約**に移っただけ。

対して同 doc でも:
- `useTheme/resolveTheme` (シグネチャ + 戻り型が doc に明記) → 全 GREEN
- `SummaryCard` (props 4 つを §6.1 メトリクスから確定でき、§8.1 に不変条件) → 全 GREEN
- `ThemeToggle` / `AppShell` (testid 存在のみ + 最小 router/auth mock) → GREEN

つまり「doc にシグネチャ or 入力契約があるものは通り、無いものだけ落ちる」線引きが明瞭。

### 追加の How to apply
- Architect: 「Reviewer がこの View を render して testid X を検証する」と書く項目は、
  その View が消費する **query の data shape** (型) を doc に転記する。
  例: `month query data = { currentBalance:number|null, endingBalanceForecast:number,
  incomeForecast:number, expenseForecast:number, records:Record[], bundles:Bundle[] }`。
  派生値 (useMemo で組む summary 等) を testid 検証が踏むなら、その派生元 query も明記。
- 代替として、空状態のような「データ非依存で出る UI」は **presentational に切り出して
  props (`records: Record[]`) で render させる**設計にすると、query mock 不要で Reviewer が
  純粋に検証できる (prop 契約だけで済む)。doc 段階でこの切り出しを指定すると検証可能性が上がる。
- Reviewer: query mock を当て続けて render を通そうとすると「実装当てパズル」になり検証機能が
  死ぬ。2〜3 形試して通らなければ `it.skip` + 理由明記で止め、YELLOW として
  「doc に query data shape が無く該当 testid を render 検証不能」を Leader に上げる。

