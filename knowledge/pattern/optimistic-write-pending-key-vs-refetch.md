---
title: 楽観更新と「再取得で全置換」を共存させる — pending キーを store 契約に載せる
category: pattern
project: omatase
tags: [state-management, optimistic-update, refetch, store-contract, testability, reducer]
created: 2026-07-30
sources:
  - Muraki/projects/omatase/.designs/20260730-rebuild-screens.md (§6.1(3) 再取得の coalesce / §6.2 store の契約 / #D10-#D15)
  - Muraki/knowledge/pattern/ws-thin-event-refetch-plus-response-delta.md
model-era: opus-4.8
---

## Context

「薄い通知 → REST で snapshot を取り直して全置換」でライブ更新する設計 (上記 pattern) に、
**タップで即反映する楽観更新** (チェックボックス / 完了ボタン) を載せるとき。
再取得は WS 通知・再接続・時刻境界・前景復帰・自分の書き込み後の 5 契機で走るので、
**1 秒に何度も snapshot が着地する**。

## What

楽観更新と全置換は素朴に共存できない。押した直後に snapshot が着地すると、サーバーがまだ
書いていない値で上書きされて**チェックが戻る (巻き戻り)**。

設計 doc に「送信中フラグのある行はサーバー値で上書きしない」と**不変条件だけ**書いても
実装できない — **フラグを立てる action と、それを置く state が契約に無い**からである
(omatase の初版は action 8 個のどれもフラグを立てず、Reviewer はこの不変条件のテストを
書けずに黙って落とした)。

成立する形は、store 契約に次を足すこと:

- state: `pendingResponses: Record<string, { target: "on"|"off"; previous: "on"|"off" }>`
- key: **純関数** `pendingResponseKey({ plan_id, kind, item_id | null })` (共有パッケージ)
- action 2 つ: `beginFeatureWrite(ref & {state})` / `settleFeatureWrite(ref & {ok})`
- `hydrate` の規則: **同じスコープの snapshot なら**、snapshot を入れた後に pending の `target` を
  自分に**再適用する**
- ★ **`hydrate` の規則 (0) — スコープ境界**: **snapshot のスコープ ID (`event_id` 等) が現在の
  state のそれと違うなら、揮発性フィールドを持ち越さない** (`pendingResponses` / WS 由来の
  presence / チャット履歴を全部捨ててから snapshot を入れる)。**初回 (state 側が null) は
  「同じスコープ」扱いで持ち越す** — snapshot より先に着いた WS の値を捨てると、次の通知まで
  空表示になる
- 遅延した自分の broadcast を無視する規則: `event_member_id === me` かつ pending 中なら適用しない

## Why

- **`previous` を持つのは巻き戻しのため。** 「失敗したら反転する」では、連打で `previous` が
  化けて元に戻せない (2 回目の begin で `previous` を上書きしないのが要点)
- **順序 (snapshot → pending 再適用) が仕様**。逆順だと pending が消える
- **key を純関数に切り出す**と、mobile (zustand) と web (reducer) で同じ文字列になり、
  「片方だけ todo の key が衝突する」が起きない
- **pending の指す行が snapshot から消えていたらエントリを捨てる** (ホストがその項目を削除した)。
  ここを書かないと「消えた行に永久に楽観値を被せ続ける」実装が生える
- ★ **「壊してはいけないもの」を列挙した瞬間、それは「スコープをまたいでも持ち越す」と読める。**
  store がアプリ全体で 1 個 (zustand の単一 store / 1 個の Provider) なら、A を閉じて B を開いた
  ときに **A のチャットが B の画面に出る**。omatase では doc を「イベントをまたい / 別イベント /
  `event_id` が変わ / 揮発」で grep して**該当 0 件**、実装は正典に忠実 = **実装バグでなく
  設計の未文書化**だった (2026-07-30)
- ★ **後始末を「呼び出し側 (画面遷移)」に置く案は、経路依存のバグを構造的に残す。** 画面遷移 /
  deep link / 再接続 / 戻る操作のどれか 1 経路で忘れれば再発し、`reset` 系 action が無く描画テスト
  基盤も無いリポジトリでは**その守りが永久に自動検証されない**。判定材料 (両方の ID) が
  `hydrate` の中に既に揃っているなら、状態遷移側の契約に置く方が安い。
  明示 action (`openEvent` / `replaceEventSnapshot`) に割るのが正しくなるのは
  **描画/結合テスト基盤が入ったとき**

## How to apply

- 「楽観更新する」と決めた設計では、**不変条件だけでなく状態遷移 (どの action がフラグを立て、
  どの action が降ろすか) を契約に書く**。書いていない不変条件は実装不能でテスト不能
- **store は「reducer 単体で呼べる純関数」として export する** (`eventReducer(state, action)` +
  `initialEventState`)。Provider/hook の中に閉じ込めると、描画テスト基盤の無いリポジトリでは
  この種の不変条件が丸ごと無検証になる
- 挙動仕様には最低 4 ケース置く: (a) pending 中の hydrate で値が残る (b) settle 後の hydrate で
  サーバー値に戻る (c) 失敗 settle で `previous` に戻る (d) 連打しても `previous` が化けない
- ★ **さらにスコープ境界の 3 ケースを置く**: (e) **別スコープ**の snapshot で hydrate すると揮発 3 点が
  空になる (f) **同スコープ**なら従来どおり持ち越す (= 既存項の対照) (g) **初回** (state 側 null) は
  持ち越す。既存の (a)-(d) の標本には「同一スコープ ID」と 1 行足す — 書かないと Reviewer が
  スコープを変えた標本を選んで対照が崩れる
- ★ 「壊してはいけないもの」を列挙する節は、必ず**その上に「同じスコープのときに限る」という段 (0)**
  を持たせる。3 項目だけ残すと「常に持ち越す」と読めて実装が割れる
