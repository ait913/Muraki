---
title: アップロード保存層の fail-closed 既定 — capability 参照 + 所有者変更 / コンテンツ由来の拡張子 / 等分チャンク規則 / 変種プリセット
category: pattern
project: nexom
tags: [upload, storage, authorization, pillow, xss, dos, chunked-upload, nexom]
created: 2026-10-21
sources:
  - Muraki/projects/nexom/.designs/20261021-storage-deps-hardening.md
  - Muraki/projects/nexom/.knowledge/security-audit-20261021/C-data.md
---

## Context
Nexom の ParallelStorage / MultiPartUploader (public_id を URL に載せる保存層 + チャンクアップロード + 画像変種キャッシュ) を一般ユーザー受け入れ前に安全既定へ倒した設計で採った判断。同種の「ID をクライアントが持ち回る保存層」に再利用できる。

## What
1. **参照は capability、変更は所有者**: 変更系 (delete / update / commit / chunk) は `pid: str` 必須で `meta.pid != pid` を専用例外。参照系 (`getMeta` / パス導出 / 変種生成) は `pid: str | None` を **既定値なしの必須引数** にし、`None` を書いた所だけ「URL を知っている者は読める」モデルで通す。暗黙の fail-open が消え、`pid=None` を grep で監査できる。閲覧者 ≠ 所有者の配信 (ユーザーアイコン等) が実在するので「全部所有者必須」は成立しなかった。
2. **保存名の拡張子はコンテンツ由来**: 画像は `Image.open(path, formats=[JPEG,PNG,GIF,WEBP])` の `im.format` から決め (`.jpg/.png/.gif/.webp`)、非画像は小さな allowlist の宣言拡張子だけ通し、それ以外は `.bin`。宣言名は `original_suffix` 列に別置き。SVG / HTML / ポリグロットが `.svg` `.html` 名で nginx の拡張子由来 Content-Type に乗るのを根で止める。
3. **等分チャンク規則**: `chunk = ceil(size/total)`、`count < total-1` は `chunk` バイト、最後は端数、と長さを固定して `len(blob) != expected` を拒否。1 セッションのディスク使用が `size` に固定され、`min_chunk_size` で inode 爆発、`max_active_uploads_per_pid` で未完了分の総量が束なる。総量クォータはアプリ側 (プラン依存)。
4. **変種キャッシュはプリセット丸め**: 寸法 (64…4096 の 11 段) と品質 (50/70/85/95) を「要求値以上で最小」に丸め、拡大はしない (contain)。パス導出関数と生成関数が同じ丸めを通るので呼び出し側は生の値を渡す。変種の総数が有界になりキャッシュ爆発が消える。
5. **ピクセル上限は Pillow 既定に頼らない**: `MAX_IMAGE_PIXELS` 超は警告のみ、2 倍超で初めて例外。`Image.open` 直後 (ヘッダのみ) に `w*h` を自前上限 (48 MP を通す 50M) で検査して例外にする。

## Why
- public_id 系はランダム 192bit で列挙不能だが「URL を知っている人」モデルは暗黙だと fail-open と見分けがつかない。明示の `None` で設計意図をコードに残す。
- アップロード側の MIME / 拡張子は攻撃者入力。配信側 (nginx alias / X-Accel) は拡張子で型を決めるので、保存名を決める側で潰すのが唯一の一点。
- チャンクアップロードの DoS は「サイズ合計」より「件数 × 1 件の上限」で起きる。長さを固定すると検査が O(1) で済み、ディスク使用の上界が宣言 `size` になる。

## How to apply
- 新しい保存層を設計するとき、メソッド表を「参照 / 変更」で 2 分し、参照系の第 1 引数を `pid: str | None` (既定値なし) にする。
- 画像の allowlist は `Image.open(formats=...)` に渡す。非画像の allowlist は 10 個程度で始め、必要になったら足す (`.svg` `.html` `.xml` `.js` は入れない)。
- チャンクの「等分 + 端数」は、クライアントが **固定 C でスライスして `total = ceil(size/C)` を送る** 実装とは一致しない (size が C の倍数でない限り `ceil(size/total) < C`)。クライアント側は `total` を決めた後に `sliceSize = ceil(size/total)` でスライスし直す 1 行が要る。先にクライアント実装を grep してこの点を移行ガイドに書く (nexom 1.2.0 でリリース前ゲートに指摘された)。
- 変種のプリセットは配信側のパス導出と同じ関数を通す (手で `width-<W>` を組む配信コードは 404 になる)。
