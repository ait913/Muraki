---
title: Email Worker は「印 → raw を R2 → 索引」の順で書き、索引の失敗は throw せず照合ジョブに任せる
category: pattern
tags: [cloudflare, email-workers, r2, d1, reconciler, idempotency, postal-mime]
created: 2026-10-24
project: global
sources:
  - projects/ais-mail/.designs/20261024-phase3-ais-mail-workers.md §4
  - knowledge/library/cloudflare-email-workers-2026-10.md
---

## Context

AIS Mail (Workers 常駐のメール) の受信設計。Email Workers の `email()` が throw した時に送信側へ何が返るか (再送 / バウンス / 黙殺) は公式 docs に無い。parse (postal-mime) は全文をメモリに持ち、25 MiB 級で isolate の 128 MB に近づく。

## What

1. 宛先解決と重複の事前確認 (D1 読み取りだけ) → 拒否なら `setReject`
2. **小さな印 `pending/<id>` を先に R2 へ put**、続けて raw (`m/<mailbox>/<id>/raw.eml`) を put。どちらかが失敗した時だけ throw (または `setReject` の一時失敗文言。スパイクで throw の挙動を確かめて選ぶ)
3. ここから先 (parse・本文と添付の put・D1 の `batch`) は try/catch で包み、**失敗しても throw しない** (raw は保存済み)。成功したら印を消す
4. 定期ジョブが `pending/` だけを list し (全 raw を走査しない)、古い印ごとに「raw 無し → 印を消す / 行あり → 印を消す / それ以外 → 同じ索引関数で索引」
5. **索引は id ごとに claim (lease 付きの条件付き UPSERT) で直列化し、確定の batch の全文に claim の柵 (`WHERE EXISTS (lease_id 一致かつ期限内)`) を付ける**。一意制約に当たった時、確定済みの id が自分と同じなら何も消さず、**別の id が勝った時だけ自分の id の R2 prefix を消す** (2 つの照合ジョブが同じ印を拾って勝者の raw を消す事故を防ぐ — Codex 指摘)
6. 重複排除キー = `Message-ID` のハッシュ + 本文側 (最初の空行より後ろ + Date/From/Subject) のハッシュ。Message-ID は送信者が決めるので、それだけだと別内容のメールを潰す。転送経路が足す `Received` の差は本文側ハッシュなら無視できる
7. parse はサイズ閾値の下だけ。超えたら `message.headers` だけで索引し本文は raw のダウンロードに回す

## Why

throw の挙動が未文書なので「受理したのに消えた」を作らない唯一の点は raw の保存。印を raw より先に置くと、どの時点で落ちても照合ジョブが拾える (印だけ残る → 消す、raw まである → 索引)。照合を `pending/` の list に限ると R2 の list コストがメール総数に比例しない。

## How to apply

- 受信処理を `handleInbound(msgLike, env, ctx)` と `indexStoredRaw(...)` の 2 関数に切り、照合ジョブも後者を呼ぶ (同じコードで索引)。テストは偽メッセージで直接呼び、索引の失敗はテストモードのフラグで注入する
- 負のコントロール: raw の put を外す → raw 一致のテストが赤 / try/catch を外す → 索引失敗で throw するテストが赤
- D1 の batch は文ごとに 1 クエリと数え、1 呼び出し 1,000 クエリ・1 文 100 bound 変数に収まるよう照合ジョブの件数を決める (添付 100 個の 1 通で約 110 クエリ)
- 試験: 索引者 2 本を確定の直前で止め、lease 切れの後に両方を進めて、確定した id の全オブジェクトが残ることを見る
