---
title: dev アプリの接続先を実行時に切り替える — container 作り直し + 既定環境だけ既存名の保存先分離
category: pattern
tags: [flutter, riverpod, env-picker, multi-environment, keychain, drift, dev-tools]
created: 2026-10-04
project: bloom
sources: [projects/bloom/.designs/20261004-env-picker.md, projects/bloom/.knowledge/research-20261004-env-picker.md]
---

## Context
同じ dev ビルド (bundle id 1 つ) で dev1 / dev2 / … のサーバーを選び直したい。接続先は const (`--dart-define`) で、ローカル状態 (Keychain の refresh token、DB 内の「登録済み」「復元済み」「送信済み」フラグ) は全部環境非スコープだった。baseUrl だけ差し替えると push 未登録・軌跡復元スキップ・足跡未送信が静かに起きる。

## What
- **保存名**: 既定環境 (ビルド時の接続先) は既存の DB ファイル名・Keychain キーのまま、他の環境は `bloom.<envTag>.sqlite` / `k1.<envTag>.<namespace>.<id>`。`envTag` = 接続先 host の先頭ラベル (改名できる表示名は使わない)。本番の保存名は 1 バイトも変わらず移行コード 0 行
- **DB ファイルごと分ける**と、DB 内の環境依存フラグは全部自動で分かれる。選択は DB を開く前に要るので DB の外 (アプリコンテナ内の小 JSON) に置く。Keychain はアプリ削除後も残るので選択の保存先に向かない
- **切替 = 旧環境へサインアウト (await) → 旧ツリーをアンマウントして 1 フレーム待つ → container 破棄・DB close → 選択を保存 → (任意で対象環境の端末データ削除) → 新 container を起動 → マウント**。保存・起動の失敗は旧環境に巻き戻す。全 provider を個別に invalidate する方式より取りこぼしが無い
- 接続先の候補はビルドに焼く (`--dart-define-from-file` の 1 値。JSON 配列は flutter_tools が `'$key=$value'` で define 化するため Dart の toString になって壊れる — `名前=URL;…` の文字列にする)。サーバーから実行時に取る案は、IPA 同梱トークンと公開経路を増やす割に、Universal Link の entitlements 追加で結局再ビルドが要るので見合わない (Touri 裁定 2026-10-04)。prod ビルドでは const 折り畳みで一覧ごと消え、preflight の文字列検査で 0 件を確かめる

## Why
環境依存状態を 1 つずつ「キーに環境名を足す」で分けると、全数を洗い出せたかに正しさが懸かる。DB ファイル単位・container 単位で分ければ、未知の状態も含めて境界ごと分かれる。既定環境だけ既存名にするのは、本番の Keychain 読み取り経路 (オプションが一致条件に入る) に移行コードを入れる危険を避けるため。

## How to apply
- 環境 (テナント) をまたぐローカル状態を設計するとき、まず「境界ごと分けられる単位 (ファイル / container)」を探し、キー単位の分離は境界の外にあるもの (Keychain 等) だけにする
- 保存名の識別子は改名されない物 (host 等) から導き、表示名と分ける
- プロセス単一のもの (GlobalKey・チャネルのハンドラ・static コールバック) を列挙し、新旧ツリーを同じフレームに共存させない
