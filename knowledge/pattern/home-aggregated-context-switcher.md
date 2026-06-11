---
title: ホーム画面に「自分 / グループ」を chip で集約する context switcher パターン (TimeTree 風)
category: pattern
tags: [home-screen, context-switching, chip-nav, timetree, calendar-app, mobile-first]
created: 2026-05-28
project: global
sources:
  - https://timetreeapp.com/ja
  - Atender v9 設計 .designs/20260528-v9-timetree-rework.md
  - knowledge/pattern/timetable-app-ux-patterns.md
  - knowledge/pattern/mobile-first-bottom-tab.md
---

## Context

カレンダー / 時間割 / 出欠など「個人ビュー」と「複数のグループビュー」の両方を持つアプリで、ホーム画面のナビ設計に悩む場面。代表例:

- TimeTree (個人 + 家族 / 友人グループ)
- Atender (自分の時間割 + ルーム = 学校友達グループ)
- Penmark (個人時間割 + 友達タイムライン)

旧設計は「個人ホーム」と「グループ一覧」を別タブで分けることが多いが、ユーザーが「今日の予定」を確認する時に**個人とグループを切替える往復が増える**。

## What

**`ContextChips` (horizontal scroll) + `ViewModeTabs` (segmented) + `Body` (dispatcher) の 3 層構造**でホーム画面を組む。

### 構造

```
┌──────────────────────────────────────┐
│  ◯自分  ◯Group1  ◯Group2  ◯+         │  ← ContextChips
│  ════════════                         │     active は accent ring + 薄塗り
├──────────────────────────────────────┤
│  [モードA] [モードB]                   │  ← ViewModeTabs (segmented)
├──────────────────────────────────────┤
│ (= context × mode の dispatcher 結果) │  ← Body
│                                       │
└──────────────────────────────────────┘
```

### context 型

```ts
type Context =
  | { kind: "self" }
  | { kind: "group"; groupId: string };
```

### dispatcher 例

```tsx
function HomeBody({ context, mode }: Props) {
  if (context.kind === "self") {
    if (mode === "A") return <SelfModeA />;
    return <SelfModeB />;
  }
  if (mode === "A") return <GroupModeA groupId={context.groupId} />;
  return <GroupModeB groupId={context.groupId} />;
}
```

### context-conditional な CTA

「ある操作は self context だけ」のように、context によって表示有無を切替える。**Body 外側に置いた CTA でも `context.kind === "self" && mode === "X"` で gate**する:

```tsx
{context.kind === "self" && mode === "timetable" ? <MainAttendanceCTA /> : null}
```

### chip の構成

- 「自分」chip は**常に先頭**、固定
- グループ chip は加入順 (= `createdAt asc` で API 返却)
- 末尾に `+` ボタン (グループ追加・参加画面へ遷移)
- 各 chip は `aria-pressed={active}`、active は accent ring + 薄塗り
- horizontal overflow scroll (mobile)、`max-w-[14ch]` で名前 truncate

### State 管理の置き場所

`context` / `mode` / `subKey` (例: semesterId) は**ホームコンポーネントのローカル state** に持つ。URL に持たない理由:
- chip 切替で毎回 navigation するとアニメ / scroll position が崩れる
- 戻るボタンで意味のある履歴は「タブ間遷移」レベルで十分

ただし将来 deep-link する要件が出たら `useSearch` 等で URL 反映可能 (現状不要)。

## Why

- **個人とグループを 1 画面で切替できる** → ユーザーは BottomTab 移動なしで予定を見れる
- **chip = 軽量、tab より階層が浅い** → タブを増やさず横方向に拡張可能 (グループ数 N に応じて自動)
- **dispatcher パターン**で既存 component を再利用しやすい (個人ビュー = 既存個人 page、グループビュー = 既存グループ page をそのまま import)
- TimeTree (国内 4000 万ダウンロード超) で実証済の UX。学習コストが低い

## How to apply

新規アプリで適用するチェック:

- [ ] ホーム画面は ContextChips + ViewModeTabs + Body の 3 層
- [ ] 「自分」chip を先頭に固定、末尾に `+` で追加導線
- [ ] active chip は accent ring + 薄塗り、`aria-pressed` を必ず付ける
- [ ] context × mode の dispatcher を 1 component に閉じる (大きくなったら switch を別関数化)
- [ ] context-conditional な CTA は外側で gate (Body 内部に書かない)
- [ ] state は URL でなくローカル (deep-link 要件が出るまで)

逆に**やらない**:

- グループの個別 page を BottomTab に並べる (n タブで増殖、5 タブ縛りを超える)
- 個人とグループを別タブで完全分離 (= 切替コスト増)
- chip を縦並びにする (mobile で縦 space 食い、horizontal scroll が定石)

## 反例 / 限界

- グループ数が極端に多い (50+) ユーザーには chip horizontal scroll の発見性が落ちる。長期的には search filter or pin 機能が必要 (MVP 範囲外)
- PC では chip を縦 sidebar に置く案もある (= Slack のチャンネル一覧パターン)。Atender v9 は PC でも mobile と同じ horizontal chip を採用 (画面構造の一貫性を優先)
- 「すべてのグループを merge」ビューを欲しがるユーザーには別 chip (例: 「すべて」chip) が要る。Atender v9 は出席率がグループ単位で意味を持たないため不採用
