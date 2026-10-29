---
title: AIS Mail サービス送信 API (POST https://mail.aisaba.net/api/v1/send) — 内製アプリが aisaba.net から送るための I/F
category: library
tags: [ais-mail, cloudflare, email-sending, service-token, aisaba]
created: 2026-10-30
project: global
sources:
  - projects/ais-mail/src/service-api/routes.ts
  - projects/ais-mail/src/service-api/token.ts
  - projects/ais-mail/src/service-api/admin.ts
  - projects/ais-mail/src/send/enqueue.ts
  - projects/ais-mail/src/send/attempt.ts
  - projects/ais-mail/.designs/20261024-phase3-ais-mail-workers.md (§6)
---

## Context

atender の Magic Link 送信を Resend から AIS Mail に移す設計前調査 (2026-10-30) で、コード (main) を一次ソースとして確定した外部送信 I/F。Pass の招待メールは別経路 (assertion の管理 API) でこの API は使わない。

## What

- 本番 `https://mail.aisaba.net` は稼働中 (`GET /healthz` 200 `ok`、`POST /api/v1/send` 無認証は 401 JSON を実測)。CF Access 等の前段なし。
- `POST /api/v1/send`、`Authorization: Bearer aism_svc_<10 文字>.<43 文字>`、`Content-Type: application/json` 必須 (他は 415)。本文 6,291,456 byte まで (413 `payload_too_large`)。
- 要求: `to` (string | string[]、`"名前 <a@b>"` 形式も可) / `cc` / `bcc` (合計 1〜50) / `subject` (1〜998 字) / `text` と `html` (どちらか必須、合計 1 MiB) / `reply_to` (単一アドレス) / `headers` (`In-Reply-To` と `References` のみ、他は 400 `header_not_allowed`) / `attachments[]` (`filename`, `content_base64`, `content_type?`、10 個・計 3 MB) / `idempotency_key` (1〜128 字 `[A-Za-z0-9._:-]`)。**`from` を含めると 400 `from_not_allowed`** (差出人はサービス登録時に固定)。
- 応答: 202 `{ id, status: "sent"|"queued"|"sending"|"failed" }` (15 秒まで待つ)。**`failed` も 202 で返る** (`routes.ts:14` の AMBIGUOUS コメント、`attempt.ts:8`): 初回試行が恒久エラー (再試行しない分類・差出人の再検査失敗) で終端になった場合で、そのメールは二度と送られない。呼び出し側は `failed` を失敗として扱う。同じ idempotency_key + 同一本文は 200 `{ ..., duplicate: true }`、本文違いは 409 `idempotency_conflict`。エラー形は `{ error: { code, message, details? } }`: 401 `unauthorized` / 403 `service_disabled` / 400 各種 / 413 / 429 `rate_limited` (+ `Retry-After` 秒) / 500 `internal`。
- **202 は「配信成功」ではない**。transport 失敗は outbox に残り、cron で最大 6 回 (backoff 1 分→5 分→15 分→1 時間→3 時間) 再試行、恒久エラー (`E_RECIPIENT_SUPPRESSED` 等) は failed。呼び出し側は失敗を同期で知れない (Mail の管理画面 failed24h / events `send.failed` で見る)。
- 差出人: サービス登録時に `from_local` (`noreply` / `no-reply` / `notify` / `svc-<a-z0-9->{1,28}` のみ) + `from_domain` (env `MAIL_DOMAINS` = 現在 `aisaba.net,n-wasabi.org` のみ。サブドメイン不可) + `from_name` (表示名) を固定。`atender@aisaba.net` のような任意 local は不可。
- レート: サービス単位で既定 30/分・500/日 (PATCH で 1〜600 / 1〜10000)。拒否された要求も枠を消費。
- トークン発行: Mail 画面 設定 → サービス送信 → サービスを追加 (管理者 = `is_admin` のメールボックスのみ)。平文は発行・再発行時に 1 回だけ表示。HMAC(SERVICE_TOKEN_PEPPER) で保存。再発行で旧トークン即無効、無効化は受理済みの送信待ちも止める。API だけでの発行手段はない (管理 API は Mail セッション認証)。
- DNS (aisaba.net、2026-10-30 実測): SPF `v=spf1 include:_spf.mx.cloudflare.net ~all`、DKIM `cf2024-1._domainkey`、DMARC `v=DMARC1; p=reject;`、`cf-bounce.aisaba.net` に MX/SPF。Outlook/Gmail 到達は 2026-10-23 実測済み (Outlook は初回 SCL 5 で迷惑メール行き、認証は全 pass)。日次送信上限は Cloudflare 非公開、月 3,000 通込み。

## Why

Resend を使わず Cloudflare Email Sending に寄せる (ais-mail 規約)。サービス送信は Pass 停止中も動く。

## How to apply

- 呼び出し側は固定 from を前提に `to / subject / text / html / idempotency_key` だけ送る。表示名は Mail 側 `from_name` で決まる。
- Magic Link のような即時性が要る用途は、202 の status が `sent` でない時の扱い (ユーザーには「送信しました」で良いか) を設計で決める。atender の採用例: `sent`/`queued`/`sending` は成功、`failed` と 2xx 以外は失敗 (`projects/atender/.designs/20261030-magic-link-mail-via-ais-mail.md`)。
- 呼び出し側のタイムアウトは 15 秒より長くする (Mail が最大 15 秒待ってから `sending` を返すため。15 秒ちょうどで切ると「後で届くのにエラー」が最も起きやすい)。
- 新しい from ドメイン (appily.run 等) を使うには Mail の `MAIL_DOMAINS` 変更 + デプロイが要る (Email Sending 自体は 3 ゾーンでオンボード済み)。
