---
title: TanStack Query Polling 設計 (refetchInterval 値の選び方と動的停止)
category: pattern
project: global
tags: [tanstack-query, polling, refetchInterval, sqlite, performance, ux]
created: 2026-05-26
sources:
  - https://tanstack.com/query/latest/docs/framework/react/guides/polling
  - https://github.com/WiseLibs/better-sqlite3/blob/master/docs/performance.md
  - https://sqlite.org/wal.html
  - OMATASE-demo polling 設計 (Muraki/projects/omatase-demo/.knowledge/00-research-summary.md)
---

## Context

リアルタイム性が必要だが SSE / WebSocket を導入するほどではない場面 (MVP・遅延数秒許容・stateless backend) で、TanStack Query の `refetchInterval` で polling を組む際の値の選び方と停止戦略。

## What

### 用途別 refetchInterval 値の目安

| 場面 | 値 | 根拠 |
|---|---|---|
| **チャット (active)** | `2000` (2s) | 公式 docs の典型値、UX 上「リアルタイム感」の閾値 |
| **チャット (background tab)** | `5000` (5s) または停止 | active より緩く |
| **時刻ベース状態 (進行ページ等)** | `10000` (10s) | 10 秒粒度の判定で UX 十分 |
| **静的データ (参加者リスト等)** | `30000` (30s) | 更新頻度低い |
| **集計データ (集合直前は高頻度)** | dynamic `5000` ↔ `15000` | 状況で切り替え |

### 動的停止パターン (★推奨)

```ts
useQuery({
  queryKey: QK.scheduleChat(scheduleId),
  queryFn: fetchChat,
  refetchInterval: (query) => {
    if (document.visibilityState !== "visible") return false;
    if (query.state.data?.scheduleStatus === "completed") return false;
    return 2000;
  },
  refetchIntervalInBackground: false, // default だが明示
  refetchOnWindowFocus: true,
  refetchOnReconnect: true,
  staleTime: 0, // polling 時は stale 即時
});
```

### refetchInterval が関数形式の挙動

- 関数は **Query オブジェクト** を受け取る (`query.state.data` で最新値にアクセス可)
- `false` を返すと polling 停止
- 数値を返すと次回 interval として使われる
- 「特定条件まで聞き続けて、達成したら止める」polling に適する

### SQLite 負荷見積もり (better-sqlite3 + WAL)

- 読み込み: index hit で **microsec〜1ms**
- 単一プロセスでも **5000+ req/sec** 余裕 (better-sqlite3 公式 perf doc)
- 書き込みは serialize されるが、毎秒数十なら詰まらない
- **WAL mode 必須**: 接続時に `db.pragma("journal_mode = WAL")`

スケール試算: 同時 50 イベント × 平均 10 接続 = 500 client active = 250 req/sec のチャット polling → 余裕

### Polling vs SSE/WebSocket トレードオフ

| 観点 | SSE | WebSocket | Polling |
|---|---|---|---|
| 単一コンテナ運用 | 接続数で FD 上限詰まる | 同上 + 状態管理重い | ✅ stateless |
| 切断検出 | hard (heartbeat 必要) | easy (ping/pong) | ✅ next poll で気付く |
| 実装コスト | 中 | 高 (再接続/認証) | ✅ low |
| 遅延 | <1s | <100ms | 2-30s (用途別) |
| デバッグ | network tab で見える | binary 多くて辛い | ✅ 完全可視 |

**Polling 採用基準**:
- MVP フェーズ
- 遅延数秒許容
- 単一 container / stateless backend
- SQLite 等のシングルライター DB

Phase 2 で SSE/WS への置換が必要になっても、TanStack Query hook を 1 箇所書き換えるだけで対応可能。

## Why

- 「とりあえず 5 秒」で全部固定すると、チャットは遅すぎ + 静的データは無駄打ち → **用途別に分離**
- background tab で polling 続けると無駄な SQLite load + バッテリー消費 → **visibility で停止**
- 永続的な状態 (例: `completed`) になったら polling 続ける意味ない → **動的停止**
- `staleTime: 0` を明示しないと、polling が走っても cache が stale 判定にならず UI が古いまま表示される事故 (TanStack Query default は staleTime: 0 だが、global default 変更がある場合保険)

## How to apply

1. **設計 doc に polling 表を書く**: queryKey × refetchInterval × 停止条件 を表形式で明示。Reviewer がテスト生成しやすい
2. **`refetchInterval` は関数形式デフォルト**: 数値 hardcoded は静的データだけにする
3. **`refetchIntervalInBackground: false` を明示**: default だが、レビュー時の意図伝達に有効
4. **共通 useQuery hook を作らない**: TanStack Query は hook 単位で意図が明確な方が読みやすい。共通化は queryKey と invalidate target のみ ([[pattern/tanstack-query-invalidation-matrix]])
5. **DB は WAL mode を起動時に有効化**: 一度設定すれば DB ファイルに記録される

## 落とし穴

- ❌ `refetchIntervalInBackground: true` をデフォにする → モバイル端末のバッテリー消費 + サーバ負荷
- ❌ `refetchInterval: 1000` を全画面に適用 → SQLite write contention で書き込みが詰まる
- ❌ polling と Mutation の onSuccess invalidate を併用する時、両方の競合で UI が一瞬古い値を表示 ([[pattern/tanstack-query-invalidation-matrix]] 参照)
- ⚠ `enabled: false` で開始 → user 操作で `enabled: true` パターンは refetchInterval 効かないことがある (v5 で改善されたが要 spot 確認)

## 関連

- [[pattern/tanstack-query-invalidation-matrix]] — Mutation 後の cache invalidate
- [[library/better-auth-hono-drizzle-sqlite]] — 同 stack 構成
- [[pattern/polymorphic-feature-plugin-sqlite]] — Feature state polling の対象 schema
