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

`primaryContentSections[].content` に heading/paragraph/table/tabNavigator/aside 等の
ブロック構造で全文が入る。Dynamic Type 表などの table・タブ切替コンテンツも全部取れる。

## Why
2026-07 の HIG 調査で WebFetch が4連続で本文空振り。JSON 直叩きに切り替えて全11ページを完全取得できた。
存在しないページ (旧 HIG の navigation 等) は 404 が返るので「現行 HIG に無い」ことの確認にも使える。

## How to apply
curl で取得し、パーサで markdown 化する。実績パーサ: 2026-07-05 セッションの scratchpad
`hig_parse.py` (inline/table/tabNavigator 対応、約80行。必要なら research-apple-hig-20260705.md の手順から再作成)。
