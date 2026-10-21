---
title: 自作テンプレートエンジンに自動エスケープを後付けするときの契約 (Markup 型 + render は Markup を返す)
category: pattern
project: global
tags: [xss, template, autoescape, markup, wsgi, nexom, python]
created: 2026-10-21
sources:
  - Muraki/projects/nexom/.designs/20261021-http-hardening.md §4
  - Muraki/projects/nexom/.knowledge/security-audit-20261021/B-http.md (HTTP-01)
  - cyber-security-agent/reports/aisaba-nexom-20261012.md (AIS-01)
---

## Context

正規表現 1 パスの `{{ slot }}` 置換器 (Nexom ObjectHTML) にエスケープが無く、本番で HTML 注入が実証された。既存アプリは「部品を render → 親の render のスロットに渡す」「`"\n".join(cards)` で合成」「Python 側で組んだ HTML 文字列をスロットへ」を多用していて、素朴に全スロットをエスケープすると全ページが `&lt;div&gt;` だらけになる。

## What

後付け自動エスケープを壊さずに入れる最小契約は次の 5 点で足りる (markupsafe を入れる必要はない。`__html__` プロトコル互換にしておけば後から差し替え可)。

1. `Markup(str)` を定義し、`escape(value)` は `Markup` / `__html__` を持つ値だけ素通し、他は `html.escape(str(v), quote=True)`
2. **`render()` の戻り値を `Markup` にする** — これだけでネストした部品合成が無修正で動く
3. `Markup` で Markup を返すメソッドは `+` / `join` / `format` の 3 つに限定し、`strip` / f-string は str に落ちると明示する。合成は `Markup("\n").join(parts)`、Python 側の HTML は `Markup("<i>{}</i>").format(user_value)`
4. テンプレート作者が書く部分 (`<Insert>` の中身、`<Import>` の展開) はエスケープしない。エスケープは「呼び出し側が渡した値」だけ
5. エスケープで防げないコンテキストは別ヘルパに切る: URL 属性は `safe_url()` (Markup 入力も信用せず `html.unescape` で文字参照を復号 → スキーム allowlist、`\x00-\x20` を除去してから判定 — `java\tscript:` / `jav&#x61;script:` 対策 → 常に escape して返す)、JS へ渡す値は `json_script()` (`<`/`>`/`&` を `<` 等に)。スロットの位置分類は**テンプレート全体を 1 パスで走査する簡約 HTML トークナイザ** (DATA / TAG_OPEN / IN_TAG / ATTR_VALUE_DQ / _SQ / _UNQUOTED / COMMENT / BOGUS / CDATA / RAWTEXT) で行い、許すのは DATA と引用符付きテキスト属性だけ。`on*` / `srcdoc` / `style` 属性、引用符なし属性、`<script>` / `<style>` 本文、タグ名・属性名位置、コメント・CDATA 内のスロットはテンプレート読み込み時に例外にする。正規表現や「直近の `<` からの状態機械」は Codex 独立レビューで `title="a < {{x}}"` (引用符内 `<` でリセット) / `<p/onclick=` (`/` 区切り) に 2 パス連続で迂回され、第 3 パスでは **script の escaped / double-escaped 状態** (`<script><!--<script>//</script>{{x}}</script>` — 最初の `</script>` は double-escape の解除にしかならない) と **foreign content (svg/math) 内の `<![CDATA[`** (`<svg><script><![CDATA[//</script>{{x}}]]>`) で迂回された。必要なのは: **引用符内で状態を変えない・`/` を属性区切りに読む・RAWTEXT は終了タグまで続く・script は HTML 仕様の `<!--` / `<script` / `-->` 副状態を追う・要素スタックで svg/math の深さを持ち、深さ > 0 では `<![CDATA[` を CDATA 状態、script/style を通常要素として追い内側を拒否する・深さ 0 の `<![CDATA[` は bogus comment**。ここまで揃えないトークナイザは穴になる (HTML 仕様の tokenizer 状態を省くたびに迂回が 1 つ生まれた)。escape 方式自体は 1 種類のまま変えず、トークナイザは拒否と属性判定にだけ使う (方式の選択を判別精度に依存させない)
6. **Markup の素通しは要素本文位置だけ**。ネストした render 出力は生の `"` を含むので、属性値位置 (ATTR_VALUE_DQ / _SQ) では Markup でも escape する。`safe_url()` の戻り値だけは非公開サブクラス (`_AttrSafe`) で属性値位置も素通しにしないと二重エスケープになる。非公開にしても直接生成は防げないので「生成は safe_url() だけ」を規約として doc に書く (Codex 独立レビュー第 1・第 2 パス、2026-10-21)

## Why

- 「render が str を返す」設計のまま autoescape を入れると、ネスト合成の全箇所に `Markup(...)` を書かせることになり移行コストで既定 True を諦めがち (段階導入案が出る)。戻り値型を変えるだけで移行箇所が「join と Python 側 HTML 文字列」に絞れる
- `escape(None)` を `""` にすると表示消失バグの発見が遅れる。従来の `str(None)` を維持する方が安全側
- `javascript:` は escape 対象文字を含まないので、エスケープだけでは URL 属性の XSS は消えない。別ヘルパが要るのは設計時に明示しないと落ちる

## How to apply

- 既存アプリの移行 grep: `"\n".join(` / `"".join(` でレンダ結果を合成している箇所、`f"<` で HTML を組んでスロットに渡している箇所、`href="{{` `src="{{` のスロットにユーザ由来値が入る箇所
- Reviewer 向けには「ネスト 1 回だけエスケープ」「Insert 素通し」「再展開なし (`{{ v }}` を値に渡しても 2 回目は置換されない)」をテスト項目に入れる
- `ErrorResponse(status, message)` のような「常にユーザ由来を疑うべき入口」は Markup を渡されても escape する (素通し例外を作らない)
