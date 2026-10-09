---
title: drift の onUpgrade はトランザクションで包まれず user_version は migration 後の別文 — 途中で落ちた DB は「表は進んだのに版が古い」状態で二度と開けなくなる
category: gotcha
project: bloom
tags: [drift, sqlite, migration, user_version, flutter, idempotent-migration, sqlite-busy]
created: 2026-10-09
sources:
  - ~/.pub-cache/hosted/pub.dev/drift-2.34.3/lib/src/runtime/executor/helpers/engines.dart (_runMigrations)
  - ~/.pub-cache/hosted/pub.dev/drift-2.34.3/lib/src/runtime/api/db_base.dart (beforeOpen)
  - projects/bloom/.designs/20261009-onboarding-v2-and-store-shots.md §13
  - projects/bloom/.designs/20261009-headless-engine-db-contention-fix.md
---

## Context

bloom の dev ビルドで接続先を dev1 に戻すと `boot_failed` (`SqliteException(1): no such table: post_drafts`)。4→5 の migration が `INSERT … SELECT … FROM post_drafts` で落ちていたが、その表は同じ migration の最後で `DROP` するもの。「版は 4 なのに表は 5 の状態」の DB が端末に残っていた。

## What

- drift 2.34.3 `_runMigrations`: `oldVersion` を読む → `user.beforeOpen()` (この中で `MigrationStrategy.onUpgrade` が走る) → **その後に別文で** `PRAGMA user_version = N`。`beforeOpen` は `onUpgrade` を `transaction` で包まない。`onUpgrade` 内の各 `customStatement` / `createTable` / `addColumn` は autocommit で個別に確定する
- したがって `onUpgrade` の最後の文 (例: `DROP TABLE old`) が確定した後、version の書き込みが失敗 (`SQLITE_BUSY`: 別コネクションが同じファイルを `busy_timeout 0` で持っていた) か プロセス kill されると、**次回以降は毎回同じ `from` で同じ migration が走り、既に無い表を読んで落ち続ける**。アプリは起動不能
- `Migrator.createTable` は `CREATE TABLE IF NOT EXISTS` なので表の再作成は無害だが、`ALTER TABLE ADD COLUMN` (duplicate column)、`INSERT … SELECT FROM <dropped>`、`DROP TABLE` (IF EXISTS を付けていれば無害) は再実行で落ちる

## Why

drift は「migration は 1 回しか走らない」前提で設計されており、原子性は SQLite の DDL トランザクションに頼っていない (DDL はトランザクション可能だが drift が BEGIN しない)。複数コネクション (headless engine 等) や kill が重なると前提が崩れる。

## How to apply

- `onUpgrade` の各段を**現在の状態を見て省略できる形**にする: `sqlite_master` で表の有無、`PRAGMA table_info` で列の有無を見てから `ALTER` / `INSERT … SELECT` / `DROP` を実行する。壊れた DB も次の起動で version が追いつき自然に直る (ファイルを消す必要がない)
- 起動経路の DB open 失敗を catch したら、drift を通さず `sqlite3.open(path, mode: OpenMode.readOnly)` で `userVersion` と `sqlite_master` の表名一覧をログに残す。症状の切り分けがこれ 1 行で済む
- 同じファイルを複数コネクションで開く構成は migration と相性が最悪 (`busy_timeout 0` が既定)。コネクションを 1 本にし、保険として `pragma busy_timeout` を `setup` で設定する (bloom の headless 修正)
- 「migration で落ちた」報告は、落ちた文だけでなく**その migration ブロックの最後の文が既に確定していないか**を疑う
