---
title: polymorphic Feature プラグイン基盤の 3 案と選び方 (JSON config か kind ごとの実テーブルか)
category: pattern
project: global
tags: [database, sqlite, postgres, drizzle, sqlc, polymorphic, plugin-architecture, json, extensibility, type-safety]
created: 2026-05-26
updated: 2026-07-30
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

### ★ どちらを選ぶかは「誰が kind を足すか」で決まる

**この 3 案に一般的な正解は無い。** 分岐は 1 つだけ:

| 前提                                                        | 選ぶ案                     |
| ----------------------------------------------------------- | -------------------------- |
| **外部開発者が plugin を足す** / migration を回せない       | **A 案** (単一 + JSON)     |
| **kind を足すのは自分たちだけ** / 型生成 ORM を使っている   | **C 案** (manifest + 実体) |

後者で A 案を採ると、**型が消える場所が DB とアプリの境界に来る**:

- **sqlc (Go) は `jsonb` を `[]byte` にしか落とせない。** 呼び出し側ごとに手書きの
  `json.Unmarshal` が並ぶ。Drizzle の `$type<T>()` や Prisma の `Json` も
  **DB が検証しない型を TS が信じているだけ**で、実体は同じ
- **per-user state のキーに FK が張れない。** JSON 内の `items[].id` を指す
  `item_key text` は誰も検証しないので、**項目を消すと state が孤児として残る**
- **数値の桁が保証できない。** `numeric(9,6)` (緯度経度など) を掛けられない

C 案なら kind ごとの実体テーブルに `kind` 列を持たせ、**複合 FK で manifest の kind と
一致を強制**できる (「todo の manifest に meetup の実体がぶら下がる」を DB が拒否する):

```sql
create type feature_kind as enum ('meetup', 'checklist');
create table feature (
  feature_id uuid primary key, parent_id uuid not null, kind feature_kind not null, position int not null default 0,
  unique (feature_id, kind)          -- ★ PK と冗長だが複合 FK の相手として必要
);
create table meetup_feature (
  feature_id uuid primary key,
  kind feature_kind not null default 'meetup' check (kind = 'meetup'),
  lat numeric(9,6) not null, lng numeric(9,6) not null,
  foreign key (feature_id, kind) references feature (feature_id, kind) on delete cascade
);
```

⚠ **enum に値を足す migration は 2 トランザクションに割る。** `alter type ... add value` した値は
同一トランザクション内で使えない (`unsafe use of new value of enum type`)。
「値を足す」と「実体テーブルを作る」を別ファイルにする。`create type` は同一 tx で使えるので、
**初回作成だけは 1 本で済む**。

実例: OMATASE は 2026-05 の検討で A 案を採ったが、2026-07-30 に **C 案へ差し替えた**
(Postgres + sqlc、kind を足すのは自分たちだけ、という前提が確定したため)。
→ `Muraki/projects/omatase/.designs/20260730-rebuild-foundation.md` §3.2 / §9

### A 案 (単一テーブル + JSON) — 外部拡張が前提のとき

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

以下は**すべて「外部開発者が plugin を足す」前提での理由**。その前提が無いなら上の分岐表を見る。

- 「将来 plugin を公開して誰でも作れる」前提では、**DB schema を fix する B 案は破綻**。新 kind 追加のたびに migration を回す運用は外部開発者に押し付けられない
- ★ **逆に、kind を足すのが自分たちだけなら migration 1 本は誤差**。そのとき UI も API も書くのだから、テーブル 1 つ足す手間は型安全の対価として安い
- JSON は SQLite で **microsec 単位** で読み書きできる (`json_extract` は high performance、virtual column 化で更に index 可能)
- discriminated union による zod 型安全で、JSON の型は実用上「ほぼ強型」になる
- state を別テーブルにすることで:
  - 配信時の cache key を `(featureId, userId)` で安定化
  - config 更新と state 更新が衝突しない
  - 集計クエリで JOIN 不要

## How to apply

0. **★ まず分岐表で案を決める** (上記)。A 案は外部拡張が前提のときだけ。以下 1.–5. は A 案の手順
1. **kind を enum で固定しない**: Drizzle 側は `text("kind").notNull()` のみ、validation は zod schema で
2. **新 kind 追加手順** (理想):
   - zod schema に 1 entry 追加
   - フロント UI コンポーネント追加 (`<MeetupFeatureCard />` 等)
   - DB migration **ゼロ**
3. **JSON クエリは初期はアプリ層で**: backend で fetch 後に JS で処理、ボトルネックが出てから virtual column + index
4. **state は per-user 別テーブル**: 集計クエリの cost を下げる + 楽観 lock しやすい
5. **設計 doc に「Feature kind 表」を書く**: 現存 kind とそれぞれの config schema を 1 セクションで明示。Reviewer はこれを根拠にテスト生成

## 落とし穴

- ❌ **外部拡張の前提が無いのに A 案を選ぶ** — 型安全を捨てた対価に「migration ゼロ」を買うが、その利点を誰も使わない。OMATASE で実際にこれをやって差し戻した
- ❌ kind を Drizzle の `text({ enum: [...] })` で固定すると、新 kind 追加で migration 発生 (A 案では本末転倒。C 案なら**それが正しい**)
- ❌ config を column flat に展開 (`config_lat`, `config_lng`, `config_items_0`, ...) → 即座にスキーマ崩壊
- ❌ state も同じテーブルに混ぜる → admin 操作と user 操作で trigger 競合
- ⚠ json_extract index は SQLite 3.31+ 必須 (better-sqlite3 12.x は 3.45+ 同梱なので問題なし)
- ⚠ 大量データ (>100k features) になると JSON parse cost が無視できなくなる → 移行戦略を pattern として残す価値あり (本書未カバー)

## 関連

- [[pattern/tanstack-query-invalidation-matrix]] — config 更新時の cache invalidate 設計
- [[library/better-auth-hono-drizzle-sqlite]] — 同スタック構成での DB 接続
