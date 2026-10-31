---
title: 2 人対戦の中継サーバーにゲーム固有の判定を足す — 純関数の Step モジュール + 両言語で通す transcript
category: pattern
tags: [multiplayer, turn-based, websocket, go, dart, flutter, game-server, determinism, testing]
created: 2026-10-31
project: wacha
sources:
  - Muraki/projects/wacha/.designs/20261031-platform-core.md §7-11, §4-9, §7-7 (R2)
---

## Context

wacha の realtime (Go、部屋ごとの actor + Valkey に状態を原子保存) は手番・同時公開の汎用プリミティブで大半のゲームを中継するが、ヒット&ブローは「秘密をサーバーが持って判定」(Touri 裁定) が要った。中継の再接続・再起動・EXEC 応答消失の再照会 (版 `ver`) をそのまま効かせたまま、ゲーム固有の判定を差し込む形を設計した。

## What

1. **モジュールは純関数 3 つ**: `Start(in) → Step` / `Act(state, from, action) → Step | *Reject` / `View(state, to) → JSON`。`Step = {State []byte, Turn *Slot, Waiting [2]bool, End *End}`。状態はモジュールにとって不透明なバイト列で、中継側が部屋の状態と一緒に保存する。時刻・乱数・I/O 禁止 (乱数は試合の seed から)。これで中継の既存の仕組み (原子更新・応答消失時の再照会・再起動復元) にモジュールが何もせずに乗る — 「元の状態に戻す」がバイト列の保持だけで済む
2. **`Waiting` をモジュールに宣言させる**と、離脱判定 (「待たされている側が切断して 60 秒」) の汎用規則がそのまま効く。手番の概念が無い局面 (両者が秘密を入れる) も表せる
3. **`View` を毎回全量で出し、イベントを snapshot 扱いにする**と、再接続は「最後の view + その後のメッセージ」で復元でき、replay の規約が増えない
4. **終局はサーバー確定**: モジュールの `End` を `mod` イベントと同じ原子更新で確定保存する。クライアントの結果報告の一致を求める型 (クライアント合意型) と場合分けし、サーバー確定型では片方の void 報告だけ即受理 (void は記録に数えないので安全)
5. **二重実装の乖離は transcript で止める**: 本番 (Go) とクライアントのテスト用 fake (Dart) に同じ規則を書くことになる。JSON の transcript (`start` の期待 + steps の `{from, action, expect: rejected | {turn, waiting, views, end}}`) を正本として Go 側に置き、両言語の検証関数で通す。Go 側は同じ transcript を 2 回走らせて全 Step の State がバイト一致することで決定性も見る
6. 期待状態の番号 (act ごとの mod_no) は付けない: 両者が同時に操作できる局面で偽の不一致を作る。旧試合は match_id、再送は cid、手番の正しさはモジュールが今の状態で判定する

## Why

中継に「ゲームごとの if 文」を入れると、再接続・再起動・永続化の各経路にゲーム知識が漏れる。状態を不透明なバイト列 + 純関数に閉じれば、中継の不変条件 (1 操作 = 1 原子更新、版で再照会) を一切崩さずにゲームを足せる。秘密の漏洩 (View に相手の秘密を入れる) は型では止められないので、transcript の views と「相手の接続が受けた全 JSON に秘密が現れない」結合テスト + 負のコントロール (View の変異で赤) で止める。

## How to apply

- 汎用プリミティブ (手番・同時公開) で足りるゲームにはモジュールを書かせない — モジュールは「サーバーが判定・秘密・隠し値を持つ」ゲームだけ
- 中継側で Step を検査する (Turn の値域・状態の上限・View の上限・End の値域と outcome 種別の一致・Reject 理由の形式)。違反と panic は「サーバー起因の無効試合」(`server_error`) にして、記録に勝敗を残さない
- モジュールの開始 (`Start`) は試合行の作成要求より前に呼び、結果を「開始中」の永続状態に含める (再起動で Start を呼び直さない)
- 版 (protocolVersion) はモジュールが複数受けられるようにし (`PVs()`)、デプロイはサーバー → アプリの順。共通ゲームの判定でモジュール未登録・版外のモードを外す (壊れずに遊べないだけ)
