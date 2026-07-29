---
title: Swift の合成 Codable は nil をキーごと省略する — zod の bare .nullable() は必ず 400 になる
category: gotcha
tags: [swift, codable, jsonencoder, zod, hono, zod-validator, contract, ios, api]
created: 2026-07-30
project: atender
sources: ["apps/ios/Atender/Core/Models/DTOs.swift", "packages/shared/src/schemas/personalEvent.ts", "sessions/2026-07-30"]
---

## Context
atender build 13 の実機で、カレンダー画面に
「予定を取得できませんでした (サーバーエラー (HTTP 400))」が毎回出た。
`POST /api/personal-events/eventkit-sync` の body が zod validation で弾かれていた。

## What
1. **Swift の合成 `Codable` は Optional プロパティを `encodeIfPresent` で書く。
   nil のとき `"key": null` ではなく、キーそのものが JSON から消える。**
   実測 (`swiftc` でビルドした実 DTO + `JSONEncoder`):
   `location: String? = nil` → 出力 JSON に `location` キーが存在しない。
2. zod の `z.string().nullable()` は **null は許すが「キーが無い」は許さない** (`invalid_type / received: undefined / "Required"`)。
   キー欠落まで許すには `.nullable().optional()` が要る。
3. → Swift `T?` × zod bare `.nullable()` の組み合わせは、**その値が nil になった瞬間に 100% 400**。
   atender では `EventKitSyncEvent.location` / `ekLastModified` がこれで、
   「場所なしの予定が 1 件でもある」= 事実上ほぼ全ユーザーで書き出し同期が死んだ。
4. **TS で書かれた backend のテストはこれを絶対に検出できない。**
   テストは JSON を TS リテラルで組むので `location: null` を明示的に入れてしまう。
   契約の非対称 (nullable vs optional) はクライアントの encoder 実装にしか現れない。
5. 併せて: `@hono/zod-validator` の validation 失敗は `AppError` を経由せず
   `{"success":false,"error":{"issues":[...],"name":"ZodError"}}` を返す。
   `{error:{code,message}}` を期待するクライアントはこれを decode できず
   「HTTP 400」という**中身のないメッセージ**に潰れる (原因が一切分からなくなる)。

## Why
Swift は「値が無い」を optionality で表現し、JSON に落とすとき既定で "キー無し" を選ぶ。
一方 zod (TS) は「null」と「undefined」を別物として扱う。
両者の既定が食い違うので、**設計 doc に `location: string | null` と書いた瞬間に
Swift 側は `String?`、zod 側は `.nullable()` に写経され、そこが穴になる**。

## How to apply
- **リクエスト body の zod schema では `.nullable()` を単独で使わない。
  Swift/RN クライアントが送る可能性がある場所は必ず `.nullable().optional()`。**
  (逆にレスポンス DTO の `.nullable()` は問題ない — サーバは明示的に null を書くから)
- 新しい request DTO を足したら、**実物の Swift struct を `swiftc` でビルドして
  `JSONEncoder` の出力を目視する**のが最速の確認 (30 秒)。
  目視の型比較では「nil のときキーが消える」は絶対に見つからない。
- `zValidator` を使う API では、validation 失敗の envelope を
  `{error:{code,message}}` に揃える hook を入れる。揃っていないと実機のエラー文字列から
  原因に辿り着けず、切り分けにサーバ再現が必要になる。
- **回帰ガードの置き方 (atender で実装済み、2026-07-30)**:
  `apps/api/tests/fixtures/ios-eventkit-sync-body.json` = 実 Swift DTO を `swiftc` でビルドした逐語出力。
  `JSON.parse` の結果を**そのまま** body に渡し、`hasOwnProperty` で「キーが今も無いこと」を自己検査する
  (`tests/eventkit-sync-contract.test.ts` S6)。TS の型で組み直すと 200 のまま緑になり無力化するので、
  fixture は絶対に型付き literal へ写経しない。
- 封筒側は `tests/helpers/swiftDecode.ts` (Swift 合成 Codable の意味論を写した最小デコーダ) を通して assert する。
  `expect(body.error.code)` だけでは TS の optional chaining が Swift の非 Optional を再現しない。
