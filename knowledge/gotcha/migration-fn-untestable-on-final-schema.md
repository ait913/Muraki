---
title: 移行関数を「移行後 schema で立つ test DB」でテストすると no such column で必ず落ちる
category: gotcha
tags: [prisma, sqlite, migration, testing, vitest, schema-evolution]
created: 2026-06-02
project: atender
sources: [".designs/20260602-phase1-course-meeting-refactor.md", "apps/api/tests/migration-room.test.ts"]
---

## Context
カラムを A テーブルから B テーブルへ移す migration (例: Course.room → Meeting.room) のデータ移行ロジックを、テスト可能にするため service 関数 `migrateCourseRoomToMeeting(tx)` に切り出した。Reviewer が「旧形データを seed → 関数実行 → 不変条件 assert」でテストしようとした。

## What
このテストは構造的に成立しない。理由:
- atender の API test DB は `prisma migrate deploy` で**最終 schema (= 移行後)** を適用して立ち上がる (tests/helpers/db.ts の ensureTemplateDb)。
- 最終 schema では Course.room は既に DROP 済み。
- 移行関数本体は `SELECT Course.room ...` を raw SQL で実行する (移行**中**に走る前提のコード)。
- → 関数を post-migration DB で呼ぶと `no such column: Course.room` (P2010) で必ず reject。
- 旧形データの seed も不可: Prisma client の型にも生成 SQL にも room が無いので Course.room へ書けない。raw SQL で ADD COLUMN しても、関数が参照する全ての旧カラムを手で再構築する必要があり、実質 migration SQL の再実装になる。

結果: 仕様1-6 (room コピー/null保持/Course から消失/Template同様/授業なし科目/occurrence不変) は**このテスト基盤では検証不能**。実装バグではなく、テスト不能 (設計の検証戦略の穴)。

## Why
「関数に切り出せばテストできる」は half-truth。移行関数は「移行前 schema の DB」を前提に書かれるが、テスト基盤は「移行後 schema の DB」しか作れない。両者の schema が定義上ズレているので、同じ DB インスタンス上で seed→実行 が噛み合わない。

## How to apply
移行ロジックの検証は、関数切り出しではなく以下のいずれかで設計する:
1. **専用の移行前 DB を組む**: テスト内で raw SQL により「移行前 schema」を一から CREATE TABLE → seed → 関数実行 → assert → DROP。移行前 schema を test fixture として明示管理する (最も忠実だが重い)。
2. **不変条件を「移行後の正データ」で検証に置換**: 「room コピーが効いた後の Meeting.room が today / bulk 経路で正しく流れるか」を通常 API テストで担保し (仕様7-9 がこれに該当)、生 migration SQL は手動 1 回検証 or 別途 `prisma migrate diff` レビューで担保する。
3. **Architect は設計doc に「移行ロジックの検証手段」を具体化する**: 「関数化して seed→実行」とだけ書くと Reviewer がこの罠を踏む。test DB が最終 schema で立つ前提なら、移行前 schema をどう用意するかまで書く。

atender では仕様7-9 (Meeting.room が bulk/today に正しく流れる) が GREEN なので、移行の「結果」は間接的に担保されている。仕様1-6 の直接検証だけが穴。
