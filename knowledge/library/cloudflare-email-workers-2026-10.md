---
title: Cloudflare Email Workers 2026-10 — email() ハンドラ API・wrangler addresses・ローカルテスト・postal-mime のメモリ実測 (throw 時の挙動は公式未記載)
category: library
project: global
tags: [cloudflare, email-workers, email-routing, postal-mime, wrangler, send_email, binding]
created: 2026-10-24
sources:
  - https://developers.cloudflare.com/email-service/api/route-emails/email-handler/ (Oct 15 2026)
  - https://developers.cloudflare.com/email-service/configuration/email-routing-addresses/
  - https://developers.cloudflare.com/email-service/observability/local-development/routing/
  - https://developers.cloudflare.com/email-service/api/send-emails/workers-api/
  - https://developers.cloudflare.com/email-service/configuration/send-bindings/
  - https://developers.cloudflare.com/email-service/platform/changelog/
  - https://github.com/postalsys/postal-mime
model-era: sonnet-5
---

## Context

AIS Mail Phase 3 (Workers 常駐) の設計前調査 (2026-10-24)。詳細: `projects/ais-pass/.knowledge/research-phase3-mail-workers-20261024.md`。

## What

- `email(message, env, ctx)`。`message` = `from` / `to` (どちらも envelope) / `headers` / `raw: ReadableStream` / `rawSize` / `canBeForwarded` / `setReject` / `forward` (検証済み宛先のみ・`X-` ヘッダのみ付加) / `reply` (DMARC pass・1 回・元送信者宛のみ)。受信上限 25 MiB。ルール 200/ドメイン。
- **catch-all を Worker に向けられる**。wrangler top-level `addresses: ["support@d.com", "*@d.com"]` (wrangler 4.113.0+) でルールを宣言管理、`wrangler deploy` が reconcile。catch-all は apex のみ。非対話 (CI) では破壊的変更を適用せず deploy 後にエラー終了。env 配下の `addresses` は無視される (2026-09-04 changelog)。
- **throw 時に送信側へ何が返るか (再送/バウンス/ドロップ) は公式 docs に記述なし**。alchemy.run が「脱出した例外は再送可能な失敗」と書くが非公式。実機確認するまで前提にしない。
- ローカル: `wrangler dev` + `curl -X POST 'http://localhost:8787/cdn-cgi/local/email' --url-query from=.. --url-query to=.. --data-raw '<RFC5322>'`。**本文に `Message-ID` 必須**。vitest-pool-workers / Miniflare での email() テストは docs 記述なし。
- Email Sending binding: `"send_email": [{"name":"EMAIL"}]`、`env.EMAIL.send({to,from,subject,html,text,cc,bcc,replyTo,attachments,headers})` → `{messageId}`。添付 32 個・総量 5 MiB。生 MIME は `new EmailMessage(from,to,raw)` (`cloudflare:email`) で互換経路。エラーは `.code` (`E_*`)。制限 binding 変種 `destination_address` / `allowed_destination_addresses` / `allowed_sender_addresses`。ローカル simulator は ArrayBuffer 添付をシリアライズできない (base64 文字列を使う)。`remote: true` で実送。Email Sending は 2026-04-16 public beta、GA 告知なし。
- `postal-mime` 4.1.4: `PostalMime.parse(message.raw)`。全文をメモリに保持。**実測 (Node 24): 24.6 MiB (添付 18 MiB) の parse で arrayBuffers が +79〜97 MiB 上乗せ** (raw 自体に加えて)。workerd の 128 MB isolate に接近 (workerd での実測は未実施)。`attachmentEncoding:"base64"` は heap が悪化。

## Why

受信は Worker が唯一の出口で、失敗時の保証が文書化されていない。大きなメッセージは parse でメモリが 3〜4 倍になる。

## How to apply

- raw を先に R2 等へ保存してから parse。サイズ閾値で parse を省略/軽量化する。
- ハンドラを純関数に切り出して直接テスト、結合は `wrangler dev` + curl。
- Routing ルールは `addresses` で宣言し、CI では確認プロンプトが出ない前提で組む。
