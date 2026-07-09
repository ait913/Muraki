---
title: 自前AS の発行JWTに upstream token を AEAD 埋め込みするステートレス federation
category: pattern
tags: [oauth, mcp, stateless, aead, token, github, federation, jwt]
created: 2026-07-05
project: dandan-app
sources:
  - Muraki/projects/dandan-app/.designs/20260705-oauth-app-migration.md
  - Muraki/knowledge/library/remote-mcp-oauth-hosts-2026.md
---

## Context

リモート MCP サーバー（自前 Authorization Server が upstream IdP=GitHub OAuth に federate）で、
「upstream token を毎リクエスト使いたい / DB を持ちたくない（ステートレス）/ MCP client に upstream token を
平文で渡してはいけない（passthrough 禁止・confused deputy）」の3条件を同時に満たす設計。

## What

- 自前 AS が発行する access/refresh/code トークンは **HMAC 署名 JWT**（自己完結・検証は署名のみ・DB 参照ゼロ）。
- upstream token（GitHub user token 等）を **AEAD（AES-256-GCM）で暗号化した blob を JWT の claim（`ght`）に埋め込む**。
  - 署名（HMAC）= 改竄防止 / 暗号（AEAD）= client からの読み取り防止。両方かける。
  - client は JWT を base64 デコードできるが `ght` は暗号 blob なので upstream token は見えない。
- **AAD に user id（`sub`）を束縛**すると、blob を別 user の JWT に移植しても復号失敗（多重防御。外側 HMAC でも改竄は防げるが blob 単体転用も封じる）。
- code → access/refresh へ `ght` を持ち回り、refresh grant は **upstream を再度叩かず同じ `ght` を再埋め込み**（upstream token が無期限な classic OAuth App 前提）。
- 復号は Resource Server 側の TokenVerifier で行い、ctx（`TokenInfo.Extra`）に平文 upstream token を載せてツールへ渡す。
- 暗号鍵（`*_TOKEN_ENC_KEY`）は署名鍵（`*_SIGNING_KEY`）と**別 env** にすると、暗号鍵だけローテートで
  「埋め込み token の一括無効化」ができる（署名は生かしたまま upstream 認可だけ切れる）。

## Why

- DB 保管なしで upstream token を運べる = 運用/バックアップ/同期を増やさずステートレスを維持。
- passthrough 禁止（MCP 認可 spec）を満たす: client には自前 AS 発行 JWT だけ渡り、upstream token は blob。
- revoke 非対応（ステートレス JWT の代償）の緩和が鍵ローテートで効く: 署名鍵ローテート=全トークン失効、
  暗号鍵ローテート=埋め込み upstream 認可だけ失効、と粒度を分けられる。

## How to apply

- upstream 失効の検知は **実 API 呼び出しの 401 でのみ**起こる（refresh は upstream を叩かないため検知不可）。
  → repo/API を触るツールは 401 を捕捉し「再ログイン（再 OAuth）してください」の再認可導線を返す設計にする。
- `Extra["<upstream>_token"]` が空/復号不可のケースを分岐（空→再認可メッセージ / 復号失敗→401）。
- JWT サイズに注意（upstream token + AEAD + base64 が payload に載る）。gho_ 級なら問題ない。
- upstream が expiring token + refresh token を返す IdP の場合は、refresh token も暗号埋め込みし
  refresh grant で upstream refresh を回す拡張が要る（classic OAuth App は無期限なので不要だった）。
