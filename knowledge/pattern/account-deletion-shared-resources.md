---
title: アカウント削除で「他人も使う資源」を壊さない — 移譲 / SetNull + 番兵 DTO / 写しは明示削除
category: pattern
tags: [account-deletion, prisma, sqlite, migration, dto, backward-compat, app-review]
created: 2026-10-09
project: global
sources:
  - Muraki/projects/atender/.designs/20261009-build20-account-deletion-legal.md
  - Muraki/projects/atender/.knowledge/09-build20-app-review-research.md
---

## Context
Atender build 20 (App Store 初回提出) で `DELETE /api/me` を設計した。User から張られた `onDelete: Cascade` を全列挙すると、自分のデータだけでなく他人が使う資源 (自分が作ったルーム丸ごと、他人のルームに足した予定、公開テンプレ) まで消える構造だった。

## What
退会者が関わる行を 4 種に分けると、各々の扱いが機械的に決まる:

| 種類 | 例 | 扱い |
|---|---|---|
| 本人だけのデータ | 時間割・出欠・セッション | Cascade のまま |
| 本人が「所有」する共有資源 | 作成したルーム | 削除前に最古の残メンバーへ所有権 (role と `createdByUserId` の両方) を移譲。残メンバー 0 なら削除 |
| 本人が「寄稿」した共有コンテンツ | 他人のルームの手入力予定、公開テンプレ | FK を nullable + `SetNull` (匿名化して残す) |
| 本人の私的データを共有先へ「写した」行 | 個人カレンダーのルーム投影、Google 同期の写し | **SetNull にすると私的データが匿名で残る** → tx 内で明示削除 |

加えて 2 つの落とし穴:

1. **列の nullable 化は API の Optional 化と同義**。旧 iOS クライアントの `Codable` が非 Optional (`let authorId: String`) だと null で decode が落ち、その画面全体が壊れる。`MIN_IOS_BUILD` を上げないなら、DB は null・DTO は番兵 (`""`) を返し、型契約 (`z.string()`) を変えない
2. **SQLite の列 nullable 化は Prisma が table recreate (`RedefineTables`) を生成する**。`DROP TABLE` は `PRAGMA foreign_keys=OFF` が効いている前提で子行を残す。`prisma migrate deploy` 経由では OFF が効き子行は無傷 (dev.db コピーで実測)。同じ SQL を FK ON のまま流すと子テーブル (TemplateDaySlot 等) と SetNull 先が全部消える (負のコントロールで実測)。生成 SQL を手で編集しない・別ランナーで流さない

## Why
Cascade は「親が消えたら子も無意味」の宣言で、共有資源ではその前提が崩れる。SetNull は逆に「子は親なしで意味がある」の宣言なので、私的データの写しに付けると削除要求に反してデータが残る。行の意味ごとに分けないと、どちらに倒しても事故になる。

## How to apply
- 退会設計の最初に `grep -n "onDelete" schema.prisma` で User からの全 FK を表にし、上の 4 種に割り振る。`source` 列 (MANUAL / PERSONAL / GOOGLE 等) がある表は種類が行ごとに違うので、`source` で分けて扱う
- 所有権の移譲は role だけでなく、Cascade の起点になっている作成者 FK (`createdByUserId`) も付け替える (role だけ変えても作成者の削除でルームが消える)
- nullable 化する列は、旧クライアントの DTO 型 (Swift `Codable` 等) を grep し、非 Optional なら番兵で返す
- 外部トークンの失効 (Apple / Google revoke) は best-effort で DB の commit **後**に回す。トークンは削除 tx の**前**に読む。ネットワークを tx の中に入れない
- 同一ユーザーの削除要求の二重送信は、プロセス内の single-flight (userId → Promise) で 1 回にまとめる (SQLite の tx 同士の BUSY を避ける)
