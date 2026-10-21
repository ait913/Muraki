---
title: Python WSGI の既定上限 — multipart (defnull) はサイズ無制限、gunicorn はヘッダ CR/LF を 400 で遮断
category: library
tags: [python, wsgi, gunicorn, multipart, dos, header-injection, nexom]
created: 2026-10-21
project: global
sources:
  - .venv/lib/python3.13/site-packages/multipart.py:926-960 (multipart 2.0.1 MultipartParser.__init__)
  - .venv/lib/python3.13/site-packages/gunicorn/http/wsgi.py:22,278-279,363-369,389-390 (gunicorn 26.2.0)
  - .venv/lib/python3.13/site-packages/gunicorn/config.py:913-975
  - https://nvd.nist.gov/vuln/detail/CVE-2018-1000164
---

## Context
Nexom (自作 WSGI FW) の HTTP 層セキュリティ監査で、FW が自前で検査していない項目を「下層 (multipart / gunicorn) がどこまで守るか」で切り分けた。

## What
- `multipart` (defnull、PyPI 名 `multipart`。`python-multipart` とは別物で `from multipart import MultipartParser` が通るのはこちら) 2.0.1 の `MultipartParser` 既定は `partsize_limit=inf`, `disk_limit=inf`。docstring にも "Both are unlimited by default" と明記。効くのは `part_limit=128`, `memory_limit=8MB` (フィールド用), `headersize_limit=4KB` だけ。呼び出し側が `content_length` も渡さなければ 1 パートで数十 MB を一時ファイルに丸ごとスプールする (30MB を実測で受理)。
- gunicorn はアプリが返すレスポンスヘッダを `HEADER_VALUE_RE = r'[ \t\x21-\x7e\x80-\xff]*'` で `fullmatch` 検証し、CR/LF 等の CTL が入ると `InvalidHeader` → 400 Bad Request (CVE-2018-1000164 の修正 19.5.0 以降)。アプリ側が無検証でも gunicorn 配下では応答分割は起きない。ただし他 WSGI サーバやユニットテスト (start_response を自前で呼ぶ) では生で通る。
- gunicorn はリクエストの `PATH_INFO` を `unquote_to_wsgi_str` で復号して渡す → `%2e%2e` も `%0a` もアプリには `..` / 改行として届く (トラバーサルは resolve で止まるが、ログに改行が入る)。
- gunicorn 26 は HEAD / 204 / 304 の body を RFC 9110 準拠で自動的に落とす (`_response_omits_body`)。アプリが HEAD を GET と同じ handler に流しても body は漏れない。
- gunicorn 既定上限: `limit_request_line=4094`, `limit_request_fields=100`, `limit_request_field_size=8190`。QUERY_STRING はこれで頭打ちになるので `parse_qs(max_num_fields=None)` でも実害は小さい。

## Why
FW 層が「サーバ任せ」にしている項目は、サーバの種類と版で守られ方が変わる。multipart の無制限既定は「ライブラリが安全側に倒してくれる」という思い込みを裏切る代表例。

## How to apply
- `MultipartParser(stream, boundary, content_length=<CL>, partsize_limit=N, disk_limit=N, part_limit=M)` を必ず渡す。Content-Length も自前で上限チェックしてから渡す (chunked だと CL が無い)。
- レスポンスヘッダは FW 側でも gunicorn と同じ正規表現で検証しておく (サーバ非依存に)。
- ログは復号後 PATH_INFO の `\r\n` をエスケープしてから書く。
