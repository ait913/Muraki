---
title: ポータブル設計のリアルタイム救命系スタック (Hono + Prisma+PostGIS + 自前 ws + Expo Push)
category: pattern
tags: [architecture, portable, realtime, postgis, expo, hono, prisma, jwt]
created: 2026-05-10
project: global
sources:
  - Muraki/projects/tsunagu/.designs/20260510-mvp-foundation.md
  - Muraki/CLAUDE.md (ポータブル設計の鉄則)
---

## Context

「位置共有 + 即時通知 + 双方向 WS」を要求する救命/防災/オンコール系アプリ。
ベンダーロックを避けたい (DB_URL + JWT_SECRET + APIキーの差替えだけで他環境に持って行きたい) が、
Supabase / Firebase / Auth0 / Vercel KV を使うと移植性が壊れる。

## What

ポータブル制約下で揃う構成:

| 層 | 採用 | NG (理由) |
|---|---|---|
| Mobile | Expo + React Native + TS | — |
| Backend | Hono (Node) | Cloudflare Workers (KV依存)、Vercel Functions (Edge制約) |
| DB | PostgreSQL+PostGIS (任意ホスト) | Supabase Postgres / Vercel Postgres (ベンダーロック) |
| ORM | Prisma + `Unsupported("geography(Point, 4326)")` | — |
| Auth | 自前 JWT (HS256, access 1h / refresh 30d) | Supabase Auth, Firebase Auth, Auth0, Cognito |
| Realtime | 自前 `ws` (Hono compatible) + in-memory pub/sub | Supabase Realtime, Pusher, Ably |
| Push | **Expo Push** (Expo SDK 経由で FCM/APNs 抽象) | FCM 直, APNs 直 (移植性低) |
| Storage | S3 互換 (`@aws-sdk/client-s3`、MinIO/R2/AWS S3) | Supabase Storage, Firebase Storage |
| Mail | Resend (HTTP API) | SendGrid 専用 SDK (差替不能) |
| KV | **使わない** | Vercel KV, Cloudflare KV |
| 配信スケジューラ | MVP は `setTimeout`、スケール時 BullMQ+Redis | — |
| デプロイ | Coolify (任意 VPS) | Vercel/Netlify (Function 依存) |

PostGIS の使い方 (空間検索):

```sql
-- 半径 N メートルのユーザー抽出
SELECT id, expoPushToken
FROM "User"
WHERE notificationOptIn = true
  AND ST_DWithin(lastKnownGeom, ST_MakePoint($lng,$lat)::geography, $radiusM);

-- AED 距離付き取得
SELECT *, ST_Distance(geom, ST_MakePoint($lng,$lat)::geography) AS distance_m
FROM "AedDevice"
WHERE ST_DWithin(geom, ST_MakePoint($lng,$lat)::geography, $radiusM)
ORDER BY geom <-> ST_MakePoint($lng,$lat)::geography
LIMIT $limit;
```

GIST インデックスは raw SQL マイグレーションで CREATE。

WebSocket の認証: query string に JWT (`?token=...`) を載せる (header だと WS で扱いにくい)。
ハートビート 25s ping / 120s タイムアウト。クライアントは指数バックオフ (1,2,4,8,...,30s) で再接続。

## Why

- **Expo Push を採用する理由**: Expo は OSS で抽象化が薄く、Expo Push Token は内部で APNs/FCM に振り分けてくれる。Expo を捨てる時も Token を `getExpoPushTokenAsync` から `getDevicePushTokenAsync` に差し替えれば FCM/APNs 直に移行可能。CLAUDE.md の「ベンダーロック禁止」を満たしつつ実装コストが最小。
- **PostGIS を採用する理由**: 半径検索 (`ST_DWithin`) と空間 GIST インデックスは PostgreSQL+PostGIS の標準機能で、どこの VPS でも動く。Supabase / Firebase の独自空間機能に依存しない。
- **自前 ws を採用する理由**: Pusher/Ably は数百同時接続なら無料枠でも、MVP 段階で「他 SaaS への移植」を検討する場面で詰む。`ws` は Node に同梱 (実質依存ゼロ) で、Coolify の長時間プロセスで動く。
- **JWT HS256 で十分な理由**: MVP は単一サーバ、複数 audience なし、Refresh は DB 不要 (期限切れで自然失効)。RS256 にする価値は鍵管理コスト的に見合わない。

## How to apply

新規プロジェクトで「リアルタイム救命/オンコール/位置連携」を作る時:

1. **`prisma init` 直後に `extensions = [postgis]` を有効化**、PostgreSQL Provider を選ぶ
2. **空間カラムは `Unsupported("geography(Point, 4326)")`** で宣言、GIST インデックスは raw SQL マイグレーションで追加
3. **Hono ルートを `routes/` に薄く積む**、ロジックは `services/` に分離
4. **JWT は `services/jwt.ts` に集約**、access/refresh 両発行、middleware で `ctx.user` 注入
5. **Push は `services/push.ts` で抽象化** (`sendToTokens(tokens, payload)`)、内部で `expo-server-sdk` を呼ぶ
6. **WS は `ws/server.ts` で起動**、room を `Map<sessionId, Set<WebSocket>>` で in-memory 管理。スケール時は Redis Pub/Sub に差替
7. **S3 アクセスは `services/s3.ts` に集約**、MinIO ローカル / 本番 R2/AWS S3 を `S3_ENDPOINT` 切替
8. **配信スケジューラ MVP は `setTimeout`**、要件が固まったら BullMQ+Redis に置換 (interface だけ先に切る)
9. **env を 1 つの `env.ts` で zod 検証**、必須キー漏れを起動時に弾く
10. **docker-compose で `postgis/postgis:16-3.4` + `minio/minio` + `mailhog` をローカル起動**、CI も同じイメージで testcontainers

参考実装: `Muraki/projects/tsunagu/.designs/20260510-mvp-foundation.md` の §2/3/4/14。
