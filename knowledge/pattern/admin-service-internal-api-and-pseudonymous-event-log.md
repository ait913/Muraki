---
title: 管理画面サービスの分離 — 本体 DB に繋がない admin + 内部専用 listener (HMAC) + 仮名イベントログで KPI を raw→mart
category: pattern
tags: [admin, internal-api, hmac, pseudonymization, kpi, event-log, sqlite, oidc, go, bloom, wasawasa]
created: 2026-10-10
project: global
sources: [projects/bloom/.designs/20261010-admin-service.md, projects/wasawasa/.designs/20261010-oidc-admin-grants-multi-app-env.md]
---

## Context
bloom (Go API + Postgres) に運営用の管理画面 (ユーザー管理・BAN・KPI・通信監視) を別サービスで足す設計 (2026-10-10)。「管理系を足して攻撃面を広げない」「KPI の定義変更を本体の改修無しで回したい」が要件。

## What
- **admin は本体 DB に接続しない**。読み取り専用ロール案は、admin 侵害で全行が読める・列権限の保守漏れ・スキーマ知識の二重化で却下された。代わりに本体に**別 mux・別 listener** の `/admin/v1/*` を生やし、Traefik に出さない (ポートを公開しない)。公開 mux に admin route が載らないことを両 mux の route 列挙テストで保証する。proxy 経由ヘッダ (`X-Forwarded-For` / `CF-Connecting-IP` 等) を持つ要求は 403 にする保険
- 内部 API の認証は **HMAC (method + RequestURI + ts + nonce + sha256(body) + actor)**、±60 秒・nonce 再利用拒否・秘密は複数受理でローテーション。actor (OIDC の sub/role/step-up 時刻) をヘッダで伝え、本体側でもロールと step-up を二重に判定。bearer 1 本はリプレイ・改ざんを防げない
- 共有契約 (DTO・署名・route) は本体 module の **stdlib のみ依存の公開パッケージ**に置き、admin module は `replace ../server` で import (go.work は本体のビルドに影響するので使わない)。Dockerfile の build context はリポジトリルート
- 内部 API 用に**別の小さい DB プール** (max 3 + statement_timeout) を作り、ユーザー通信のプールから隔離
- **KPI は admin 側で raw → mart**。本体は行為の時点で**仮名イベント** (HMAC(秘密, user_id)、秘密は本体だけ) を送り出しバッファ表に書き、admin が seq で pull。ソース表から日次集計すると、脱退・退会の CASCADE で過去が縮む。mart は SQL ファイル群で raw から全再構築 (定義変更が過去分にも効く)
- 仮名側と実ユーザー側を**結合させない規則**: 本体に user_id↔仮名の変換 API を作らない / export に user_id を出さない・ユーザー管理の応答に仮名や活動時刻・正確な件数を出さない / **退会・BAN をイベントにしない** (仮名の消滅時刻が墓標の退会日と突き合わさる)
- 閲覧系の利用 (地図を開いた等) は、アプリが**前景のときだけ付けるヘッダ** + route→機能の対応表で取る。位置アプリは背景起動で API が走るので、route だけだと水増しされる。投稿単位の閲覧は取らない (既読ログになる)
- admin の自前ストアは SQLite (`modernc.org/sqlite`、cgo 不要): 監査 (append-only を trigger で)、セッション、検出候補、KPI 倉庫
- **アカウントへの管理操作 (BAN・強制ログアウト・紐付け直し) の失効は sessions 削除では足りない**。stateless な access JWT と upload token が期限まで生きる。`users.auth_valid_after` (秒に切り上げ) と JWT の `iat` の比較を認証の共通処理に入れ、upload は本人分を消す。正キャッシュは値ごと持つ
- **共通の proxy ログを各環境の admin にマウントしない**。収集器 1 つだけが生ログを読み、環境別・許可列挙のフィールドで書き出す (招待トークンは日替わり HMAC にして数だけ数えられる形に)
- 外部の取り消し (SIWA revoke 等) を挟む管理操作は「予約 (検証込み) → 外部 → 実行 (再検証)」の 2 段にし、途中失敗は予約行の状態から再開する
- HMAC の nonce はプロセス内でなく DB の一意制約で消費する (再起動・rolling update の旧新コンテナをまたぐ再送)
- IdP (better-auth `mcp()`) を共用するときは、claim をサーバー秘密の HMAC binding を持つ静的 client にだけ載せ、RP は aud を厳密照合。DCR を開けたままでも管理画面は守れる

## Why
管理画面は「内部の人しか使わない」ので手を抜かれがちだが、本体 DB の資格情報を持たせた瞬間に最大の攻撃面になる。API 経由に絞れば被害範囲は API が許す操作に限定され、全操作が本体側のログにも残る。KPI を本体から切り離すと、本体は「事実を出すだけ」で定義の議論が本体のリリースに乗らない。

## How to apply
- 管理系を足す設計では最初に「admin が侵害されたら何ができるか」を表にし、DB 直結を選ばない
- 内部 listener は「env が無ければ起動しない (fail-closed)」「公開ポートと同じなら起動失敗」を起動検証に入れる
- 仮名イベントを設計するときは「どのイベントの時刻が実ユーザー側の画面の値と 1 対 1 に突き合うか」を表にし、突き合うものはイベントにしない・粗くする
- KPI の raw は「再取得で値が減っても縮めない」(max マージ / event_id 冪等) を合流規則にする
