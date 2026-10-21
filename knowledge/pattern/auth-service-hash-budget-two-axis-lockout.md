---
title: 自前認証サービスのレート制限は「安い検査 → ハッシュ予算 → 2 軸ロック」の順で、verify を login から守る
category: pattern
project: nexom
tags: [auth, rate-limit, lockout, pbkdf2, dos, sqlite]
created: 2026-10-21
sources:
  - Muraki/projects/nexom/.designs/20261021-auth-hardening.md
  - Muraki/projects/nexom/.knowledge/security-audit-20261021/A-auth.md (AUTH-04/06)
---

## Context

単一の認証サービス (PBKDF2 でパスワード検証、全アプリが `verify` に依存) に login 洪水が来ると、PBKDF2 の CPU で worker が埋まり verify がタイムアウト → 全アプリが 500 になる連鎖が起きる。Nexom 1.1.x は反復 200k で毎秒 100 弱の login で飽和 (Researcher 実測)。

## What

login 経路を次の順に並べる。

1. **安い拒否を先に**: method / JSON / 必須フィールド / 長さ上限 (user_id 256 文字、password 256 byte) / IP の形式。ここは DB にも書かない
2. **ロック確認** (SQLite の `auth_attempts(key, count, window_start, locked_until)`): `login_ip:<ip>` と `login_user:<id>` のどちらかが `locked_until > now` なら 429。ロック中の試行はロックを延長しない
3. **プロセス内の時間ベース PBKDF2 ゲージ**: 直近 1 秒窓でハッシュに費やした実測 wall time (`perf_counter`) が 50% を超えていたら 429。回数 (4 hash/s) で切ると測定機の速さを定数に焼くが、比率なら機械が変わっても verify に残す割合が不変。sync worker は 1 要求ずつなので verify の待ちは「走っている 1 ハッシュ分」に有界
4. **試行枠を予約**: 両軸を 1 文の `INSERT … ON CONFLICT DO UPDATE SET count = CASE 窓切れ THEN 1 ELSE count+1 END` で +1 してから `SELECT count`。閾値超なら戻して 429 (ハッシュしない)。これで「ロック確認 → ハッシュ → 加算」の隙間に別 worker が割り込んでも閾値が厳密上限になる
5. PBKDF2 — **未知ユーザーでもダミー salt で 1 回計算** (タイミング差を消す)、`is_active` は一致判定の**後**
6. 失敗なら予約をそのまま確定 (閾値到達で `locked_until`)。成功ならアカウント軸は行削除、IP 軸は −1 (IP 軸は失敗だけ数える)。再認証 (パスワード変更・管理操作のパスワード再入力) も同じキー・同じ順序を通す — ここを素通しにすると login のロックを別経路で総当たりされる

既定値: アカウント 5 回 / 15 分 → 15 分ロック。IP は失敗 30 回 / 15 分 → 15 分ロック。signup は IP で 10 回 / 時 (形式検証とゲージを通過したもの)。

## Why

- 予算が無いと「レート制限はあるのに verify が死ぬ」が残る。分散 IP の攻撃者は窓を越えずに PBKDF2 を回せるため、CPU の上限は回数制限と別に要る
- IP 軸で成功も数えると NAT 配下 (学校・社内) の正規利用者が巻き込まれる。失敗だけ数えれば credential stuffing には効き正規利用者には効かない
- `(user, ip)` の組でロックすると、IP を回す攻撃者には永久に発火しない。アカウント単位の 15 分ロックの DoS 面は受容する
- ダミーハッシュは予算を消費させることで「存在しない ID を叩いて予算だけ空にする」攻撃と「存在する ID を叩く」攻撃のコストを同じにする

## How to apply

- `AuthPolicy` 相当の frozen dataclass に数値を集め、テストでは `refill_per_sec=0.0` と注入 `clock` で決定的に検証する
- 設計 doc では「カウント順序」(どの段で何を加算するか) を番号付きで固定する。Reviewer が A12 と A11 の加算有無を迷わない
- 残存リスク (アカウントロック DoS、legacy ハッシュのタイミング差、分散低速攻撃の上限回数) を doc 末尾に数値で書く
