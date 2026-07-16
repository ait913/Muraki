---
title: Apple developer docs は SPA — JSON エンドポイント直叩きで全文取得
category: library
project: cross
tags: [apple, hig, webfetch, research]
created: 2026-07-05
sources:
  - https://developer.apple.com/tutorials/data/design/human-interface-guidelines/typography.json
---

## Context
HIG や developer.apple.com/documentation を一次ソースで精読したいとき。

## What
developer.apple.com のページは SPA で、WebFetch では `<title>` しか取れない (本文ゼロ)。
本文データは docs JSON にある:

- HIG: `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<slug>.json`
- 通常 docs: `https://developer.apple.com/tutorials/data/documentation/<path>.json`
- **ローカライズ版 HIG: `https://developer.apple.com/tutorials/data/<locale>/design/human-interface-guidelines/<slug>.json`**
  (例: `.../data/ja-JP/design/human-interface-guidelines/sign-in-with-apple.json` → 200 + 日本語全文)

### ローカライズ版の取り方 (2026-07-16 実測)

`?language=ja-JP` / `?locale=ja-JP` / `Accept-Language: ja-JP` は**いずれも効かない** (200 だが英語のまま。`language=` は DocC の interfaceLanguage=swift/objc 用)。`/jp/tutorials/data/...` は 404。**パスに locale セグメントを挟む形だけが効く**。

利用可能な locale は各ページの `metadata.availableLocales` に入っている (HIG は概ね `en-US, ja-JP, ko-KR, zh-CN`)。

**なぜ効くか**: 規約の「公式日本語表記」を一次ソースで確定できる。実例 — Sign in with Apple のカスタムボタン許容タイトルは、英語版だと `Sign in with Apple` 等の3択としか書いておらず「日本語化してよいか」が読み取れないが、**ja-JP 版は「Appleでサインイン」「Appleでサインアップ」「Appleで続ける」のみを使用すること**と明記しており、日本語表記の可否と正式な字面 (助詞前後のスペース有無まで) が確定する。

`primaryContentSections[].content` に heading/paragraph/table/tabNavigator/aside 等の
ブロック構造で全文が入る。Dynamic Type 表などの table・タブ切替コンテンツも全部取れる。

## Why
2026-07 の HIG 調査で WebFetch が4連続で本文空振り。JSON 直叩きに切り替えて全11ページを完全取得できた。
存在しないページ (旧 HIG の navigation 等) は 404 が返るので「現行 HIG に無い」ことの確認にも使える。

## How to apply
curl で取得し、パーサで markdown 化する。実績パーサ: 2026-07-05 セッションの scratchpad
`hig_parse.py` (inline/table/tabNavigator 対応、約80行。必要なら research-apple-hig-20260705.md の手順から再作成)。
