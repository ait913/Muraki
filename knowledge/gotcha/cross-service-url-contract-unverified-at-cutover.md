---
title: 他サービスの設定が指す URL は切替受入で実際に叩く (設計に書いてあっても実装漏れは起きる)
category: gotcha
project: ais-pass
tags: [cutover, acceptance, cross-service, jwks, cloudflare-workers, observability]
created: 2026-10-30
sources:
  - Muraki/sessions/2026-10-29-b45758d0.md (95〜97)
  - Muraki/projects/ais-pass/.designs/20261026-go-rewrite.md §10-8 / 付録 A-1
---

## Context

AIS Pass の Go 書き直し版を 2026-10-27 に本番切替した。Mail (Cloudflare Worker) は var `PASS_SYNC_JWKS = https://pass.aisaba.net/api/auth/sync-jwks` から公開鍵を取って Pass からの assertion を検証する。設計 doc 付録 A-1 にその URL は書いてあったが、pass 側のルート表 (§21) に行が無く、実装もされていなかった (signer 内部の `/v1/sync-jwks` だけ存在)。

## What

- 切替から 3 日間、Pass → Mail の push 同期と招待メール送信が **全部 401** で失敗していた。pass のログは毎分 `mail_full_sync_failed` (理由なし、PII 配慮で詳細を出さない設計) を吐き続けていたが、誰も見ていなかった
- 発見の入口は別件 (管理画面でメール作成が `invalid_handle` になるという報告) のログ調査
- 直接の確認は `curl https://pass.aisaba.net/api/auth/sync-jwks` → 404 の 1 発。Mail 側は取得失敗をキャッシュしないので、pass にルートを足したら次の tick で全メールボックスが acked に戻った

## Why

- 切替手順 (§25) の受入は Pass 単体 (healthz / discovery / jwks の kid) で止まっていて、**Pass が他サービスに呼ばれる側の URL** を実測していない
- 設計 doc で「URL」と「ルート表」が別の節に分かれていると、片方だけ読んだ実装者が落とす
- エラーログが理由を出さない (`mail_full_sync_failed` のみ) ので、流れていても「毎分の既知ノイズ」に見える

## How to apply

1. 切替 / デプロイの受入チェックに「**他サービスの設定値 (var / env) が指す自分の URL を全部 curl する**」を入れる。grep の種は相手リポジトリの `wrangler.jsonc` / compose env / `.env.example` の `https://<自分のドメイン>`
2. 設計 doc で他サービスから参照される URL を書いたら、同じ doc のルート表にも必ず行を足す (Architect)。契約テストはルート表から生成するので、表に無い = テストされない
3. 毎分出る ERROR ログは「出続けている」こと自体をアラート条件にする (Grafana: `mail_full_sync_failed` が 10 分以上連続)。理由を伏せるログほど継続時間で検知するしかない
4. 本件の受入コマンド: `curl -s https://pass.aisaba.net/api/auth/sync-jwks | jq '.keys|length'` が 1 以上、`mail_sync_meta.last_full_push_at` が 1 時間以内
