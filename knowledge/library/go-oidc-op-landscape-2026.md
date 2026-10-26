---
title: Go で OIDC OP を作る時のライブラリ地図 (2026-10) — OP 認定は zitadel/oidc に無い、fosite は停止、better-auth の暗号文は Go で復号できる
category: library
tags: [go, oidc, op, zitadel-oidc, fosite, luikyv-go-oidc, go-jose, conformance-suite, better-auth]
created: 2026-10-26
project: global
sources:
  - https://github.com/zitadel/oidc (README, pkg/op 実コード v3.51.16)
  - https://github.com/luikyv/go-oidc (v0.25.0)
  - https://github.com/ory/fosite , https://github.com/pocket-id/fosite
  - https://openid.net/certification/certified-openid-connect-implementations/
  - https://gitlab.com/openid/conformance-suite
  - projects/ais-pass/.knowledge/research-go-rewrite-20261026.md (詳細と出典)
---

## Context
AIS Pass (Next.js + better-auth) を Go に作り直す前の調査 (2026-10-26)。

## What
- **zitadel/oidc v3.51.x は RP のみ OIDF 認定** (Basic/Config)。README の Goals に「Certify this library as OP」が残る。OP ライブラリで認定を名乗るのは `luikyv/go-oidc` (0.x、単独メンテ、FAPI/CIBA/VC まで含む巨大面積)。Pocket ID (fosite fork `pocket-id/fosite` を使う製品) は OP 認定。
- `ory/fosite` は v0.49.0 (2024-12) 以降リリース無し、2025-08 以降 commit 0。部品群で discovery/JWKS/userinfo/Storage は全部自前。
- zitadel/oidc の Storage は約 23 メソッド (AuthStorage 14 + OPStorage 8 + Health)。RFC 9207 `iss` 応答パラメータは**未実装**、PKCE は method 空 = plain を許す、refresh の再生ウィンドウは無い (Storage 任せ)。2026-08 に不透明 access token の非認証暗号で認証バイパス (GHSA-j8gq-92xf-382c、3.47.0 で修正)。
- OIDC Discovery 1.0 §3 は `id_token_signing_alg_values_supported` に **RS256 を必ず含める** (MUST)。ES256 のみ広告すると conformance の Config OP で落ちる見込み。
- OIDF conformance suite はローカル Docker で回せる: `docker-compose-prebuilt.yml` (mongo + server + nginx、`https://localhost.emobix.co.uk:8443`、hosts 追記要) と `scripts/run-test-plan.py`。計画名 `oidcc-basic-certification-test-plan[...]` / `oidcc-config-certification-test-plan`。ログインはブラウザ自動操作 JSON なので GitHub+TOTP のような対話認証にはテスト専用経路が要る。
- better-auth 1.7.12 の `jwks.privateKey` 列は `JSON.stringify("$ba$<ver>$<hex>")`、hex = XChaCha20-Poly1305 の `nonce24 || ct`、鍵 = `SHA-256(BETTER_AUTH_SECRETS の値の文字列)`、AAD 無し。**Go の `chacha20poly1305.NewX` で復号できることを実測**。client secret / token は `SHA-256 → base64url (パディング無し)` で、Go でも同式で照合可。
- Go 1.26 系は 2026-03〜10 にセキュリティ修正入り point release が 8 回 (stdlib の net/http / crypto/tls / x509 / html/template)。pgx は 5.9.0 で CRITICAL 2 件 (memory-safety) 修正。「Go にすればパッチ追従が要らない」は誤り。

## Why
「certified OP lib」という前提は README の RP 表記を OP と読み違えやすい。契約固定の細部 (iss / sid / replay) はライブラリの守備範囲外になりがち。

## How to apply
- OP ライブラリ選定は README の認定を RP/OP に分けて読み、実コードで `iss`・refresh 再生・PKCE 方式の扱いを grep してから採否を決める。
- 既存 better-auth データを別言語へ持ち越す時は、鍵・ハッシュ・封緘を実暗号文で突合する (本ノートの式)。
- Go 製 IdP でも govulncheck + 月次 toolchain 更新の運用が必要。
