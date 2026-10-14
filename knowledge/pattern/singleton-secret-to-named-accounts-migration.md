---
title: singleton の封緘秘密を「名前付きアカウントの表」へ移す migration (URL 不変・rolling 安全)
category: pattern
tags: [migration, secrets, rolling-update, drizzle, postgres, webhook]
created: 2026-10-14
project: global
sources: [Muraki/projects/wasawasa/.designs/20261014-integration-accounts.md]
---

## Context
wasawasa で `integration_settings` のキー単位 singleton (ASC キー / Firebase SA / Webhook トークン) を、名前付きで複数登録して環境ごとに選ぶ形に変えた設計。既存の Webhook URL (トークンを path に含む) は変えられず、Coolify の rolling update で旧コンテナが数十秒重なる。

## What
1. **封緘の AAD を確かめる**: AAD が purpose 文字列だけ (行キーを含まない) なら、封緘値を SQL でそのまま新しい表へ複製できる (再封緘・TS の起動時処理が要らない)。行キーや id を AAD に含めていたら、この手は使えない
2. **スキーマ migration とデータ migration を分け、新しい CHECK はデータの後に張る**: 「有効なら新しい FK 列が非 NULL」の CHECK を drizzle の生成物 (スキーマ側) に残すと、既存の有効な行で migration が落ちる。生成物から CHECK の 2 文を手で消し、custom のデータ migration の末尾で DROP IF EXISTS → ADD する (snapshot は新 CHECK のまま)
3. **旧行はこの版では消さない**: rolling 中の旧コンテナとロールバックが旧行を読む。削除は次のデプロイの migration に分ける (秘密の削除なので承認対象)
4. **トークンを path に持つ URL を保つ**: 照合を「全アカウントの封緘トークンを開けて timingSafeEqual」にする。ハッシュの列は移行の SQL で作れない (平文が無い) ので使わない。アカウントが数件なら十分
5. **キャッシュのキーをアカウント id に**: プロセスに 1 個の JWT / access token キャッシュは、stamp を `updated_at` だけにすると、別の行の `updated_at` が同じ時に取り違える。キーと stamp の両方に id を入れる。負のコントロールは「2 行の updated_at を DB で揃える」
6. **実行中のジョブはアカウントをスナップショット**: 受付時に id と名前を run に書く。旧コンテナが入れた NULL の run は、処理時に親 (環境) の値で一度だけ埋める
7. **参照名 (slug) を最初から持たせる**: 将来、リポジトリ側の設定ファイルが名前で参照する見込みがあるなら、表示名とは別に作成後不変の slug を持たせる (後から足すと既存行の命名の移行が要る)

## Why
秘密の再封緘・URL の変更・旧コンテナの失敗は、どれも利用者から見ると「移行したら壊れた」になる。上の 7 つで、移行を SQL だけの冪等な処理に閉じ、旧版と新版が同時に動いても進行中の処理を落とさない。

## How to apply
singleton の設定を複数化する設計では、先に (1) AAD の中身、(2) 新しい CHECK が既存行で成り立つか、(3) 旧コンテナが旧行を読む経路、(4) 外部に貼った URL / ID が旧値に依存するか、を grep で確かめてから migration の段数を決める。
