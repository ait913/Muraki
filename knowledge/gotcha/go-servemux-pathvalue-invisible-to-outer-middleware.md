---
title: "Go ServeMux の PathValue / Pattern は、mux の手前で r.WithContext したコピーにしか付かない (外側 middleware からは見えない)"
category: gotcha
project: global
tags: [go, net-http, servemux, middleware, access-log, path-value]
created: 2026-10-13
sources:
  - "Go 1.26 net/http ServeMux.ServeHTTP (findHandler が r.Pattern / r.pat / r.matches を渡された *Request に書く)"
  - "bloom server/internal/httpapi/limits.go:364 (edgeAdmission が mux の手前で r.WithContext)、scratchpad の実走 2026-10-13"
---

## Context

bloom のアクセスログに route の `{gid}` 等を足す設計で、「外側の `accessLog` が `next.ServeHTTP` の後に `r.PathValue("gid")` を読めばよい」と書きかけた。

## What

`ServeMux.ServeHTTP` は **渡された `*Request` そのもの**に `Pattern` / path value を書く。外側 middleware → mux の間に `r = r.WithContext(...)` (shallow copy) をする middleware が 1 つでもあると、mux が書くのはコピー側で、外側の `r` には何も付かない。コピーが無ければ外側からも `r.PathValue` が読める (実走で確認)。

## Why

`WithContext` は `*r2 = *r` の shallow copy で、`pat` / `matches` は値フィールド。mux は handler 呼び出し直前に自分が受け取ったポインタへ書くので、分岐したコピーには伝播しない。

## How to apply

- 外側 middleware で path value が要るときは、中間に `WithContext` があるかを `grep -n "WithContext(" <middleware files>` で確かめる。1 つでもあれば **登録側 (`mux.Handle` を包む `handle` closure) で取って、外側に見えるホルダ (context に置いた可変 struct) に書く**
- 逆に「外側で読める」設計を書くなら、将来 middleware が増えても壊れない保証が無いので、ホルダ方式を既定にする
