---
title: Cloudflare Email Service 2026-10 — Email Routing (apex MX 専有、Worker は throw 時の挙動が未記載) と Email Sending (Workers Paid、3,000 通/月込み、Message-ID 指定不可)
category: library
project: global
tags: [cloudflare, email-routing, email-workers, email-sending, mx, dkim, spf, dmarc, resend, workers]
created: 2026-10-23
sources:
  - https://developers.cloudflare.com/email-service/ (Last updated Oct 15, 2026)
  - https://developers.cloudflare.com/email-service/configuration/domains/
  - https://developers.cloudflare.com/email-service/platform/limits/
  - https://developers.cloudflare.com/email-service/platform/pricing/ (Jun 9, 2026)
  - https://developers.cloudflare.com/email-service/api/send-emails/rest-api/
  - https://developers.cloudflare.com/email-service/api/send-emails/workers-api/
  - https://developers.cloudflare.com/email-service/reference/headers/
  - https://developers.cloudflare.com/email-service/concepts/email-lifecycle/
  - https://developers.cloudflare.com/email-routing/email-workers/runtime-api/
  - https://developers.cloudflare.com/workers/platform/limits/
  - https://developers.cloudflare.com/workers/observability/errors/
  - https://developers.cloudflare.com/fundamentals/reference/http-request-headers/
  - https://resend.com/docs/dashboard/domains/cloudflare
model-era: fable-5.1
---

## Context

AIS Mail (aisaba.net の Web メール) の設計前調査 (2026-10-23)。自宅 MTA を公開せず、受信 = Email Routing → Email Worker → Tunnel 越し webhook、送信 = 外部 HTTP API、で組めるかを公式 docs で確認した。詳細な比較表は `projects/ais-pass/.knowledge/research-phase1-20261023.md`。

## What

- **docs は `developers.cloudflare.com/email-service/` に再編済** (旧 `email-routing/` も残る)。製品は Email Routing (受信、Free / Paid) と Email Sending (送信、Beta、任意宛先は Workers Paid $5/月 が必要) の 2 本。
- **Email Routing を有効にすると apex に MX `route1/2/3.mx.cloudflare.net` + SPF TXT `v=spf1 include:_spf.mx.cloudflare.net ~all` + DKIM TXT `cf2024-1._domainkey` が自動追加され、apex MX は Cloudflare 専有** (「Cannot use Email Routing with external mail servers」)。送信プロバイダはサブドメイン MX (Resend は `send.<domain>`、Cloudflare Email Sending は `cf-bounce.<domain>`) なので共存できる。SPF は apex 1 本に merge する (複数 SPF 不可)。
- Email Worker: `message.raw` は `ReadableStream`、`rawSize`、`setReject` = 永久拒否、`forward` は検証済み宛先のみ (`X-` 以外のヘッダは落ちる)、`reply` は元の送信者宛のみ (DMARC pass 必須、1 回限り)。受信上限 25 MiB。Workers の CPU 制限が適用され **Free (10 ms) では `EXCEEDED_CPU` になり得ると公式が注意** → Paid 前提。
- **Worker が throw した時に送信側へ何を返すか (再送されるか) は公式 docs のどこにも書かれていない** (runtime-api / lifecycle / troubleshooting / FAQ / postmaster を確認)。第三者は「一時失敗で再送」と言うが出典無し。
- Worker から外部 HTTPS への `fetch()` に制限は無い。同 zone の hostname でも、その hostname に Worker route が無ければ Error 1042 (Worker-to-Worker) にならない。同 zone subrequest では origin の `CF-Connecting-IP` が Worker の `x-real-ip` を反映する (IP で認証しない)。
- Email Sending: REST `POST /accounts/{account_id}/email/sending/send` (Bearer API token)、Workers binding `send_email` (`env.EMAIL.send()` は `messageId` を返す、REST は返さない)、SMTP `smtp.mx.cloudflare.net:465`。メッセージ 5 MiB、宛先 50。Paid に 3,000 通/月込み、超過 $0.35/1,000。検証済み宛先への送信は Free でも無料。
- Email Sending の導入手順 (公式 get-started、2026-10-23 確認): ダッシュボード Compute → Email Service → Email Sending → **Onboard Domain** でドメインを選ぶ → `cf-bounce.<domain>` に MX / SPF TXT / DKIM TXT、`_dmarc.<domain>` に TXT が自動追加 (Cloudflare DNS 必須、5〜15 分で反映)。送信元アドレスの個別登録は不要 (オンボード済ドメインの任意アドレス)。API トークンの権限名は **「Email Sending: Edit」** (SMTP 向けに明記。REST も同じトークンで通る前提、未実測)。Email Routing の有効化は前提条件として書かれていない。
- Email Sending の上限 (platform/limits): 宛先 50 (to/cc/bcc 合計)、件名 998 字、本文 5 MiB (検証済み宛先のみ 25 MiB)、カスタムヘッダ合計 16 KB、zone あたりドメイン 30 (Routing + Sending 合計)。**日次送信上限は「新規アカウントは控えめな日次クォータから始まり自動で引き上げ」とだけあり数値非公開**、増枠は Limit Increase Request Form。REST の 429 は `email.sending.error.throttled` (10004) で閾値は非公開。
- Email Sending REST のレスポンスは **実測 (2026-10-23、aisaba.net) で `result.message_id` (`<...@aisaba.net>` 形式) を返す**。docs の「REST は messageId を返さない」は陳腐化。他に `delivered[] / queued[] / permanent_bounces[] / suppressed_recipients[]`。主なエラー: 400 `too_big` (10200) / `no_content_length` (10201) / `invalid` (10202)、401 `unauthorized` (10101) / `bad_token_type` (10103)、403 `forbidden` (10102) / `not_entitled` (10105、Workers Paid 未契約) / `sending_disabled` (10203) / `account_suspended` (10207)、429 `throttled` (10004)。
- Email Sending のヘッダ allowlist: `In-Reply-To` / `References` / `List-*` 等と `X-*` は可、**`Message-ID` は不可 (`E_HEADER_NOT_ALLOWED`、Cloudflare ドメインで生成)**、`Reply-To` は `headers` でなく `replyTo` / `reply_to` フィールド。

## Why

Email Routing のルール出口は「転送 / Worker / Drop」だけなので HTTP に出すには Worker が必須。その Worker の失敗時挙動が未記載のため、設計側でフォールバックを持たないと「origin が落ちた瞬間のメール」が行方不明になり得る。

## How to apply

- Worker は throw しない設計にする: `rawSize` で 25 MiB を確認 → origin に `fetch` (共有秘密ヘッダ、`Content-Length: rawSize`) → 失敗時は検証済み宛先へ `forward()` か KV / R2 にスプール。`setReject` は失敗時に使わない。
- 送信を Resend にするなら DNS は `send` (SPF TXT + MX)、`resend._domainkey` (DKIM、DNS only)、`_dmarc` を手動で足す。Email Sending に寄せるなら Routing と同じ zone で `cf-bounce` 配下が自動追加される。
- Message-ID を自分で決めたい用途 (threading の自前管理) は Email Sending では不可、Postmark なら可、SES は常に上書き、Resend は送信後に `GET /emails/:id` の `message_id` を読む。

## 実測 (2026-10-23、aisaba.net → outlook.com)

- 送信元ホップは `ba-ef.cloudflare-email.net (104.30.10.45)` のみ。HTTP API 経由なので送信側 (自宅) の IP はヘッダに一切出ない (AIS Pass AT1 合格)
- `Return-Path: bounces@cf-bounce.<domain>`、DKIM は `s=cf-bounce d=<domain>` と `s=cf2024-1 d=cloudflare-email.net` の 2 本、`Feedback-ID: <domain>:4:1:Cloudflare`
- **Outlook.com は初回送信を SCL 5 で迷惑メール扱い** (SPF / DKIM / DMARC は全 pass)。新規ドメインの評価不足。受信者に迷惑メールフォルダー確認を案内し、「迷惑メールではない」を押してもらう
