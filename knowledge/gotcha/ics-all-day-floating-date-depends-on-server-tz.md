---
title: ICS 終日イベント (VALUE=DATE) は floating date — サーバの TZ で UTC 実体がズレる (dev=JST / 本番コンテナ=UTC)
category: gotcha
tags: [ics, icalendar, timezone, all-day, node-ical, docker, alpine, test-flakiness]
created: 2026-07-17
project: atender
sources:
  - atender fix/ics-esm-import (f4160c2) レビュー実測
  - apps/api/Dockerfile (FROM node:20-alpine, TZ 未設定)
---

## Context

atender の ICS インポートのレビューで、終日イベントの assert が
`start: "2026-07-08T15:00:00.000Z"` (= JST 7/9 00:00) で緑になった。
`TZ=UTC` を付けて同じテストを回すと**赤くなった**。

## What

**`DTSTART;VALUE=DATE:20260709` (終日) は TZ 情報を持たない floating date で、
Node/node-ical は「プロセスのローカル TZ の 0 時」として解決する。**

| プロセス TZ | `DTSTART;VALUE=DATE:20260709` の解決結果 |
|---|---|
| `Asia/Tokyo` (Touri の開発機) | `2026-07-08T15:00:00.000Z` (= 7/9 00:00 JST ✓) |
| `UTC` (本番コンテナ) | `2026-07-09T00:00:00.000Z` (= 7/9 **09:00** JST ✗) |

対して **`DTSTART;TZID=Asia/Tokyo:20260707T130000` は TZ 非依存**で、どちらでも `2026-07-07T04:00:00.000Z`。
つまりズレるのは**終日 (VALUE=DATE) だけ**。

**`apps/api/Dockerfile` は `FROM node:20-alpine` で TZ を設定していない → 本番は UTC。**
開発機は JST。よって**手元で正しく見える終日イベントが、本番では 9 時間ズレて 09:00 に表示される**可能性がある
(atender では ICS インポート自体が壊れていて誰も到達したことがなく、未発覚のまま)。

## Why

- iCalendar 仕様上 `VALUE=DATE` は「日付」であって瞬間ではない。UTC 実体に落とす時点で必ず解釈が要る。
- Node の `Date` はローカル TZ で解釈するため、解決結果が**プロセスの TZ 設定に依存**する。
- Docker の公式 Node イメージは TZ を設定せず UTC が既定。**dev と prod で TZ が違う**構成は既定でそうなる。

## How to apply

- **終日イベントの assert に UTC の絶対時刻を直書きしない。** JST 開発機でしか緑にならないテストになる。
  TZ 非依存な不変条件で書く:
  ```ts
  const localParts = (iso: string) => { const d = new Date(iso);
    return [d.getFullYear(), d.getMonth()+1, d.getDate(), d.getHours(), d.getMinutes()]; };
  expect(localParts(allDay.start)).toEqual([2026, 7, 9, 0, 0]);      // ローカル 0 時であること
  expect(new Date(allDay.end).getTime() - new Date(allDay.start).getTime()).toBe(24*60*60*1000);
  ```
- **カレンダー系を触るなら TZ を明示的に固定する。** 選択肢は 2 つあり、これは**プロダクト判断**:
  1. コンテナ/プロセスを JST に固定 (`ENV TZ=Asia/Tokyo` / `vitest.config.ts` に TZ)
  2. floating date を明示的に JST 0 時として解釈するコードを書く (TZ 設定に依存させない)
  「サーバ TZ に暗黙依存したまま」が一番危険。
- **テストは本番の設定でも回す。** `TZ=UTC pnpm exec vitest run` を 1 回撃つだけで
  「dev の TZ に寄生した緑」を炙り出せる。同レビューではこれで 1 件検出した。
- 日本向けアプリで dev=JST / prod=UTC は**あらゆる日付境界バグの温床** (「今日」の判定、週の開始、締切など)。
  ICS に限らず疑う。
