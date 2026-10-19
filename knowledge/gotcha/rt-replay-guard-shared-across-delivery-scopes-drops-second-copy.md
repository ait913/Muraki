---
title: 同じ暗号文を 2 つの配信経路 (toggle / gathering) で配る設計では、受け手の再送検査 (seq / ts) を scope ごとに持たないと後着の経路が捨てられる
category: gotcha
tags: [bloom, e2e, realtime, replay-protection, design, testing]
created: 2026-10-15
project: bloom
sources: [bloom 0.2.3 C U3 Reviewer (feature/touri-023-e2e-u3), .designs/20261015-e2e-location-and-media.md §9-2 / §9-3 / W12]
---

## Context
bloom 0.2.3 の RT (リアルタイム位置) は、送り手が 1 グループにつき 1 つの暗号文を作り、平文の `scope` に `["toggle","gathering:<bid>"]` を両方入れる (W12)。サーバーは承諾者へ `pin{scope:gathering}`、全員へ `pin{scope:toggle}` を同じ `c` で送る (§9-3 handlePos2 の手順 3 と 6)。受け手は「同じ送り手・同じグループで直前に採用した平文が同じ dev なら seq が大きいこと」を要求する。

## What
承諾者 (ビーコンに参加していて、かつグループのメンバー) は**同じ暗号文を 2 通**受け取る。1 通目 (gathering) は採用され、2 通目 (toggle) は「seq が同じ」で捨てられる。実測 (Flutter、実 WS 配線): `toggle` の入れ物が空のまま、`gathering` にだけ入る。逆順 (toggle → gathering) だと gathering が空になる。実装は設計の文面どおりで、設計側の規則が「(送り手, グループ)」を単位にしているのが原因。

## Why
再送検査の状態キーに scope が入っていない。1 つの暗号文が 2 つの scope で意味を持つ設計なのに、検査だけは scope をまたいで 1 つの状態を共有している。

## How to apply
- 設計: 受け手の再送検査の状態は (送り手, グループ, scope[, beacon_id]) 単位にする。または、同じ `c` の再着 (seq・ts とも同値) は「捨てる」でなく「別 scope の入れ物にだけ反映」と書く。
- テスト: 「1 つの暗号文が複数の経路で届く」設計は、W12 の暗号文をサーバーの配信順どおりに 2 通流して**両方の入れ物**を見る 1 本を必ず入れる (単経路の seq / ts テストだけでは出ない)。
