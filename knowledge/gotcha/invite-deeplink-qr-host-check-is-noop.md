---
title: 招待 deeplink QR の host 検証は URL を開かない限り防御力ゼロ
category: gotcha
project: atender
tags: [security, deeplink, qr, ios, threat-model]
created: 2026-07-21
sources:
  - Muraki/projects/atender/.designs/20260721-ios-qr-invite.md
  - "Reviewer probe 2026-07-21 (feature/qr-invite)"
---

## Context

QR / universal link で招待 (ルーム参加・友達追加) を実装するとき、スキャン結果検証を
`DeepLink.parse(url) != nil` の path 構造チェックだけにすると host (`atender.appily.run`) を
見ない。`https://evil.com/rooms/join/<code>` のような別ドメイン + 正しい path 形の QR が
`.roomJoin(code:)` を返す。「host 検証を足すべきでは」という上申が出る典型構図。

## What

**host 検証の追加は、以下 3 条件が揃う限り防御力ゼロ (over-engineering)**:

1. スキャンした URL を **ブラウザ/WebView で開かない** (phishing 経路が無い)
2. 抽出するのは path 埋め込みの **code だけ**で、それを **アプリにハードコードされた自 API**
   (Bearer 認証済) に送る — scan URL の host はリクエスト先に一切影響しない
3. code は **サーバ側で検証**される (存在しない code は弾かれる)

実害が無い決定打: 攻撃者は **正規 host** `https://atender.appily.run/rooms/join/<攻撃者の code>`
の QR をいつでも作れる。host allowlist を足しても、攻撃ベクタ (= 被害者に攻撃者の code で
join/add させる) は host 非依存なので素通りする。防ぐべきものを防がない。

**逆に host 検証が要るのは**: スキャン URL を `UIApplication.open` / WebView で開く設計にした瞬間
(phishing に化ける)。その場合は host allowlist でなく「invite deeplink は絶対に外部で開かない」を
不変条件にする方が堅い。

## Why

QR 招待の脅威は「偽 host」でなく「攻撃者が選んだ code を踏ませる」こと。code の宛先が固定
(自 API + サーバ検証) なら、URL の host 部分は解析後に捨てられており、検証しても情報が増えない。
「別ドメインが通る」を見て直感的に「脆弱」と判じると、防御力ゼロの host-check を足して
コードだけ増える。

## How to apply

- Reviewer: 「host 検証が無い」上申は **probe テストで実挙動を採取** (`evil.com/rooms/join/X` を
  通す) → **抽出値の宛先を設計 doc で追跡** (自 API か / URL を開くか) の 2 段で判定。宛先が
  固定 API なら「acceptable、host-check は no-op」と結論できる。
- Architect: 招待 deeplink 設計では host allowlist を書くより **「スキャン URL は開かない・code だけ
  抽出して自 API へ」を不変条件**として明記する方が本質的。host 検証条項は防御と誤認されやすい。
