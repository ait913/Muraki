---
title: 活動フィード (通知タブ) は「宛先ごとの行 + 反応だけ partial unique で集約 upsert + 未読は端末ローカル + 再取得は既存の薄い event」で組む
category: pattern
tags: [activity-feed, notifications, push, aggregation, postgres, partial-unique-index, unread, websocket, flutter, riverpod]
created: 2026-10-09
project: bloom
sources:
  - projects/bloom/.designs/20261009-activity-feed-and-push-prefs.md (§2-2 D1/D2/D3/D8, §4-1, §5-1)
  - knowledge/pattern/ws-thin-event-refetch-plus-response-delta.md
---

## Context

BeReal 型の「アクティビティ」画面 (左アバター / 太字の名前 + 文 + 相対時刻 / 右サムネ / 期間見出し / 同じ投稿への複数人の反応を 1 行にまとめる) を、既存の push 基盤 (APNs + 薄い WS event + REST 再取得) の上に足した。サーバーは Go + Postgres、アプリは Flutter + Riverpod。

## What

1. **保存は「宛先 1 人につき 1 行」** (`activity_events(recipient_id, kind, actor_ids uuid[], post_id, …, created_at, updated_at)`)。ブロック・退出・投稿の非表示は**読み出し時**に JOIN で落とす (挿入時に除外しない)。投稿・コメント・ビーコンの削除は FK `ON DELETE CASCADE` で行ごと消す。
2. **集約するのは反応 (reaction) だけ**: `UNIQUE INDEX … (recipient_id, post_id) WHERE kind = 'reaction'` の partial unique に `INSERT … ON CONFLICT (recipient_id, post_id) WHERE kind = 'reaction' DO UPDATE SET actor_ids = array_prepend($actor, array_remove(actor_ids, $actor)), updated_at = EXCLUDED.updated_at`。新しい人が先頭、行は `updated_at` で上に浮く。取消は `array_remove` → 0 人なら DELETE (`updated_at` は進めない)。コメントは 1 コメント 1 行。
3. **ページングは `(updated_at, id)` の keyset**、cursor は `"<unixmicro>.<uuid>"` の不透明文字列。`limit + 1` 件取り、`next_cursor` は「落とす前の limit 件目」(読み出し時に actor が 0 になって捨てた行があってもページを飛ばさない)。
4. **未読は端末ローカル** (kv に「見た時点の先頭行の `updated_at`」、サーバー時刻)。タブが見えている間に (a) 選択、(b) 先頭ページ再取得完了、で書く。サーバーに既読 API を持たない = 相手に何も出ない。
5. **フィードの再取得契機は既存の group event** (`post_new` / `comment_update` / `reaction_update` / `beacon_update` / `member_update` / …) を使い、宛先ユーザーごとの新 WS kind は足さない。再取得は固定間隔 (2 秒に 1 回、in-flight 中の呼び出しは完了後にもう 1 回) で間引く。
6. **先頭ページだけ JSON のまま kv にキャッシュ**して cold start を速くする。構造化キャッシュ (drift 表) は作らない — 行の消滅がサーバー正で、マージ規則が増えるだけ。
7. 相対時刻と期間見出しは **1 つの純関数**が `(section, label)` を同時に返す (`diff < 60 分` なら暦日に関係なく「今日 / N分前」)。別々に計算すると 0:30 に 23:50 の行が「昨日」見出しの下に「40分前」で出る。

## Why

- 読み出し時に畳むと keyset cursor が集約前の行に乗り、ページ境界で同じ投稿の行が 2 つに割れる。upsert なら行は常に 1 つで「新しい反応で上に浮く」が自然に出る。
- 宛先ごとの新 WS event は、既存テストが `requireNoMessage` で「期待の 1 通の後は無音」を固定している環境では同じ接続の 2 通目になって赤くなる。契機が既存 event で全部届いているなら足す理由が無い。
- 既読をサーバーに置くと「相手に見える既読」と区別が付かなくなる (PRODUCT の「既読を作らない」原則)。

## How to apply

- フィードを足す前に、行を生む契機ごとに「既存の WS event は誰に届いているか」を表にし、宛先集合が一致するなら新 event を作らない。
- `activity_events` の列は `recipient_id / kind / actor_ids / <対象の FK 群> / body (表示の写し ≤ 80) / created_at / updated_at`。`body` は読み出し JOIN を減らすための写しで、FK CASCADE が消す対象と同じ寿命。
- 表示文は `(kind, post.mine, actors 名)` だけから純関数で生成し、サーバーは文を返さない (文言の正典をアプリ 1 箇所に置く)。
- push の種別トグルは **OFF 行だけの表** (`notification_optouts(user_id, kind)`)。既定 ON に行が要らず、新 kind は CHECK の追加だけ。フィルタは `notifyFrom` + engine の `notify` の 2 入口に同じ `FilterNotifyEnabled` を置く。
