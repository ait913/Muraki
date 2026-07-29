---
title: リアルタイム系で WS は配信専用・REST を唯一の認可関門にする
category: pattern
tags: [websocket, rest, authz, realtime, design]
created: 2026-07-23
project: omatase
sources: [".designs/20260722-ws-hub.md", ".designs/20260723-mvp-rest-and-mobile-wiring.md"]
---

## Context
位置/presence/チャット/ステータスを WS 1 本に載せるアプリ (omatase) で、REST と WS の
責任境界を設計するとき。inbound で受けるもの (location/status) と、REST 保存後に配信するもの
(message/rsvp) が混在し、認可 (role×type、event 所属) をどこに置くかが問題になる。

## What
- **WS inbound は「保存が要らず・authz が接続身元だけで決まる」もの (location/status) に絞る。**
  それ以外 (message/rsvp/announcement) は REST で受けて保存し、成功後に `hub.Broadcast` する。
- **`hub.Broadcast` は authz をかけない = 「認可済みを配るだけの口」。** 認可の責任は REST 1 箇所に閉じる。
  Broadcast を呼ぶ側が認可を通す義務を負う。
- **REST の event 配下エンドポイントは、path の `{event_id}` と「トークンから確定した member の event」の
  一致確認が唯一の関門。** ここを通さないと WS には何も乗らない (WS は authz しないので)。
- 2 認証系統 (ログイン=Supabase JWT / ゲスト=自前 member token) は **`Resolve(claims, eventID) → EventMember`
  の 1 関数に収束**させ、WS handler と REST で共有する (eventID の出所だけ違う: WS=クエリ, REST=path)。
- role×type の認可 (例 announcement は host のみ) は、その type が REST 経由でしか来ないなら **REST 側の責務**。
  WS の inbound authz (`canSend`) は location/status だけ見る。

## Why
- 認可を WS と REST の両方に置くと、同じ判定が 2 箇所に分岐して片方が腐る。1 箇所に閉じれば監査点が 1 つ。
- 時刻の権威も REST/DB に一元化できる (端末時計を無視し、保存後の値を Broadcast に載せる)。
- realtime が本当に要るのは位置/presence/chat/status だけ。plan/task/event 更新は WS type を増やさず
  「画面遷移時 re-fetch」で妥協でき、契約と authz 面の膨張を防げる。

## How to apply
- WS の type 表に「inbound 可否 / outbound / 保存先 / 誰が authz するか」を必ず 1 表で持つ。
- 「この type は誰が送れるか」を WS 側か REST 側かのどちらか一方に必ず割る (両方に書かない)。
- 2 認証系統は Claims (検証済み素材) と EventMember (DB 確定) を型で分け、確定関数を共有パッケージに置く。
- リアルタイム反映が要らない更新系は、WS type を足す前に「re-fetch で足りるか」を先に問う。
