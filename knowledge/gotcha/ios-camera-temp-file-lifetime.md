---
title: iOS camera プラグインの stopVideoRecording 一時ファイルは送信時まで生存保証がない
category: gotcha
project: bloom
tags: [flutter, camera, ios, tmp, upload, multipart]
created: 2026-08-22
sources: [bloom TestFlight build 8 投稿 INTERNAL バグ, sessions/2026-08-22-cd6ad0f4.md]
---

## Context

Flutter `camera` パッケージの `stopVideoRecording()` が返す `XFile.path` は iOS の一時領域を指す。bloom で「アップロードに失敗しました (INTERNAL)」「下書き保存に失敗しました」が同時発生し、前セッションで HTTP 層・リトライ層を 3 回修正しても直らなかった。

## What

- 一時ファイルは録画直後〜投稿確定 UI の間に iOS 側で消えることがある (プレビュー再生や画面遷移を挟むと especially)。
- 消えた後は multipart 構築が**送信前に**例外 → サーバーには何も届かないのに、アプリのエラー封筒変換で `INTERNAL` に化ける。ローカルの下書きコピーも同じ不存在パスを読むので同時に失敗し、「ネットワーク/サーバー障害」に見える。
- 決定的な切り分け: **本番アクセスログに該当 POST が 1 件も無い** = クライアント送信前の失敗。サーバー側を疑う前に必ずログの有無を見る。

## Why

iOS の tmp/caches はシステムが任意のタイミングで掃除してよい契約。パスを保持し続ける設計は「たまたま動く」だけ。

## How to apply

- 録画停止直後 (投稿確定 UI の初期化時点) に `Application Support/<app>/drafts/<client_key>.mp4` へ **即コピー**し、投稿・リトライ・下書き DB のすべてをその安定パスに統一する。
- 送信前に `File.exists()` を検査し、不存在なら HTTP を打たず専用エラー種別で「動画ファイルが失われました」UI に落とす (INTERNAL に混ぜない)。
- 失敗診断ログには「段階 (file-check / form-build / http / draft-copy / draft-db) + パス + exists + 例外型」を残す。
