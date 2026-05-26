---
title: SQLite で polymorphic Feature プラグイン基盤を組む (kind + JSON config)
category: pattern
project: global
tags: [database, sqlite, drizzle, polymorphic, plugin-architecture, json, extensibility]
created: 2026-05-26
sources:
  - https://www.dbpro.app/blog/sqlite-json-virtual-columns-indexing
  - https://sqlite.org/json1.html
  - https://orm.drizzle.team/docs/column-types/sqlite
  - OMATASE-demo Schedule × Feature 設計 (Muraki/projects/omatase-demo/.knowledge/00-research-summary.md)
---

## Context

エンティティに「種類の違う付加機能」を 0..N 個アタッチしたいケース。例:
- Schedule に Feature (集合・持ち物確認・QR出欠・...) をアタッチ (OMATASE)
- Article に Block (text / image / embed / poll / ...) をアタッチ (CMS)
- Task に Reminder Plugin をアタッチ

将来 plugin を追加する前提で、DB schema を migration 無しで拡張可能な形にしたい。

## What

### 3 案比較

| 案 | スキーマ | Pros | Cons |
|---|---|---|---|
| **A: 単一テーブル + JSON** | `feature(id, parent_id, kind, config_json, position)` | ✅ 新 kind 追加で migration 不要<br>✅ Drizzle 1 テーブル定義 | 型安全は zod / discriminated union で補強必要 |
| **B: per-kind テーブル** | `meetup_feature(...)`, `checklist_feature(...)` | 強い型 + index 細かく貼れる | kind 追加毎に migration + N 種 JOIN |
| **C: manifest + per-kind** | `feature(id, parent_id, kind, position)` + `meetup_feature_data(feature_id, ...)` | バランス | A の柔軟性 + B の手間 |

### 推奨: A 案 (単一テーブル + JSON)

```ts
import { sqliteTable, text, integer, index } from "drizzle-orm/sqlite-core";

export const feature = sqliteTable("feature", {
  id: text("id").primaryKey(),
  parentId: text("parent_id").notNull(), // schedule_id / article_id / etc.
  kind: text("kind").notNull(), // ❗ enum で固定せず string で開く
  config: text("config", { mode: "json" }).$type<FeatureConfig>().notNull(),
  position: integer("position").notNull().default(0),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
  updatedAt: integer("updated_at", { mode: "timestamp_ms" }).$onUpdate(() => new Date()).notNull(),
}, (t) => [
  index("feature_parent_idx").on(t.parentId, t.position),
  index("feature_kind_idx").on(t.kind), // 「全 meetup feature を集計」用
]);
```

`FeatureConfig` は **zod discriminated union** で型安全に:

```ts
import { z } from "zod";

const meetupConfigSchema = z.object({
  kind: z.literal("meetup"),
  location: z.union([
    z.object({ inherit: z.literal(true) }),
    z.object({ inherit: z.literal(false), lat: z.number(), lng: z.number(), label: z.string() }),
  ]),
  qrCheckIn: z.boolean().default(true),
});
const checklistConfigSchema = z.object({
  kind: z.literal("checklist"),
  items: z.array(z.object({ id: z.string(), label: z.string(), required: z.boolean().default(true) })),
});
export const featureConfigSchema = z.discriminatedUnion("kind", [
  meetupConfigSchema,
  checklistConfigSchema,
]);
export type FeatureConfig = z.infer<typeof featureConfigSchema>;
```

### per-user state は別テーブル

config (admin が設定) と state (user が更新) は life cycle / 更新頻度 / 集計クエリが全く違うので分離:

```ts
export const featureState = sqliteTable("feature_state", {
  featureId: text("feature_id").notNull().references(() => feature.id, { onDelete: "cascade" }),
  userId: text("user_id").notNull(),
  state: text("state", { mode: "json" }).$type<FeatureState>().notNull(),
  updatedAt: integer("updated_at", { mode: "timestamp_ms" }).notNull(),
}, (t) => [
  primaryKey({ columns: [t.featureId, t.userId] }),
]);
```

集計 (「全員チェック済?」) は:
```sql
SELECT COUNT(*) FROM feature_state
WHERE feature_id = ? AND json_extract(state, '$.allChecked') = 1;
```

### JSON 内フィールドで頻繁にクエリするなら virtual column + index

```sql
ALTER TABLE feature ADD COLUMN kind_status TEXT GENERATED ALWAYS AS (
  json_extract(config, '$.status')
) VIRTUAL;
CREATE INDEX feature_kind_status_idx ON feature(kind_status);
```

ただし MVP では先に JSON のまま運用、ボトルネックが出てから virtual column 追加で OK。

## Why

- 「将来 plugin を公開して誰でも作れる」前提では、**DB schema を fix する B 案は破綻**。新 kind 追加のたびに migration を回す運用は外部開発者に押し付けられない
- JSON は SQLite で **microsec 単位** で読み書きできる (`json_extract` は high performance、virtual column 化で更に index 可能)
- discriminated union による zod 型安全で、JSON の型は実用上「ほぼ強型」になる
- state を別テーブルにすることで:
  - 配信時の cache key を `(featureId, userId)` で安定化
  - config 更新と state 更新が衝突しない
  - 集計クエリで JOIN 不要

## How to apply

1. **kind を enum で固定しない**: Drizzle 側は `text("kind").notNull()` のみ、validation は zod schema で
2. **新 kind 追加手順** (理想):
   - zod schema に 1 entry 追加
   - フロント UI コンポーネント追加 (`<MeetupFeatureCard />` 等)
   - DB migration **ゼロ**
3. **JSON クエリは初期はアプリ層で**: backend で fetch 後に JS で処理、ボトルネックが出てから virtual column + index
4. **state は per-user 別テーブル**: 集計クエリの cost を下げる + 楽観 lock しやすい
5. **設計 doc に「Feature kind 表」を書く**: 現存 kind とそれぞれの config schema を 1 セクションで明示。Reviewer はこれを根拠にテスト生成

## 落とし穴

- ❌ kind を Drizzle の `text({ enum: [...] })` で固定すると、新 kind 追加で migration 発生 (本末転倒)
- ❌ config を column flat に展開 (`config_lat`, `config_lng`, `config_items_0`, ...) → 即座にスキーマ崩壊
- ❌ state も同じテーブルに混ぜる → admin 操作と user 操作で trigger 競合
- ⚠ json_extract index は SQLite 3.31+ 必須 (better-sqlite3 12.x は 3.45+ 同梱なので問題なし)
- ⚠ 大量データ (>100k features) になると JSON parse cost が無視できなくなる → 移行戦略を pattern として残す価値あり (本書未カバー)

## 関連

- [[pattern/tanstack-query-invalidation-matrix]] — config 更新時の cache invalidate 設計
- [[library/better-auth-hono-drizzle-sqlite]] — 同スタック構成での DB 接続
