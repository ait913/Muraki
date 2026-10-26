---
title: 自前 IdP の分割 — 署名専用 signer (network なし・Unix socket) + 管理 SPA の重要操作は IdP 側の確認ページで TOTP
category: pattern
tags: [idp, oidc, signer, key-isolation, step-up, admin-console, unix-socket, docker-compose, audit-sink, go]
created: 2026-10-26
project: global
sources: [projects/ais-pass/.designs/20261026-go-rewrite.md]
---

## Context
AIS Pass (内製 IdP) を Next.js から Go に書き直す設計 (2026-10-26)。検査で「1 プロセスが全秘密を読める」「管理面が公開 listener に同居」「管理系の常設 bearer token が他サービスの全権」が挙がり、RCE されたときに残るものを減らす構造を求められた。

## What
- **署名専用 signer**: 秘密鍵を持つプロセスを分け、`network_mode: none` + IdP 本体だけが mount する volume 上の Unix socket で HTTP を受ける。接続ごとに `SO_PEERCRED` の uid を検査。API は「id_token 署名」「他サービス向け短命 assertion 署名」「公開鍵」「監査追記」だけで、**iss / alg / TTL / iat は signer が自分で決め、入力に無いキーは 400**。鍵の export・任意 payload 署名は無い。JWKS は signer の応答本文を IdP がそのまま返す
- **常設の他サービス用 token を signer 発行の要求束縛 assertion に置換**: `{aud 固定, exp=iat+60, jti, htm, htu (許可 regex), bsh=SHA-256(本文)}` を ES256 で。受け側は公開鍵を var で pin し、jti を一意表で消費。持ち出しても 60 秒・その 1 要求でしか使えない
- **管理 SPA の重要操作は IdP 自身の HTML 確認ページで TOTP 再入力**: SPA は「保留中の操作」を作るだけ (202 `{opId, confirmUrl}`)、トップレベル遷移で IdP の `/confirm/{id}` を開き、IdP が DB の操作内容を表示して TOTP を受け、同じ tx で実行。操作は作ったセッションでしか確認できない。SPA の画面で TOTP を受けると、侵害された管理サーバーが表示と送信内容をすり替えられる。秘密を返す操作 (client secret) は確認ページにだけ出し、SPA を通さない
- **監査の DB 外 sink を signer に置く**: 追記専用 API + hash chain の jsonl。IdP 本体は signer の volume に書けない。DB の `audit_log` には `sink_seq` 列を持ち、トリガーで「NULL → 値 の UPDATE だけ」を許して後埋め・再送
- **pending セッションを昇格させない**: GitHub 認証後と TOTP 完了後で token を作り直す (行ごと作り直し)。`sid` を保ちたい再入力 (prompt=login) は行を残して token だけ更新
- フォーム送信の後に外部 origin へ連鎖リダイレクトすると Chrome は `form-action` を連鎖全体に適用する。JS ゼロの画面では 303 で RP へ繋がず、meta refresh の interstitial で連鎖を切る

## Why
login UI と鍵が同じプロセスにある限り、UI の RCE = 鍵の恒久窃取 + 他サービスの常設 token の持ち出し。signer を分けると、RCE 中の偽造は signer のログに残り、RCE が終われば止まる。重要操作の確認を信頼側 (IdP) に置くと、管理面が侵害されても「ログイン中の管理者の TOTP なしで出来ること」に縮む。

## How to apply
- 管理系・IdP の設計では「どのプロセスが RCE されたら何が残るか」を現行と対比の表にしてから境界を決める
- 他サービスへの常設 bearer を見つけたら、送り手が鍵プロセスを持つなら短命 assertion に置換できないか先に検討する
- 管理 SPA に step-up を入れるときは「TOTP を受ける画面を誰が描くか」を決める。SPA 側で受けるなら、SPA 配信元の侵害を脅威モデルから外したと明記する
- Docker Compose の network / volume / env 分離は Coolify 等のオーケストレータが書き換えることがある。使い捨てリソースで実測してから設計の前提にする (ais-pass の Phase 0)
