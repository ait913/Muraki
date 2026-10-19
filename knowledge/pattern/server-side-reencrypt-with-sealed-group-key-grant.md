---
title: 既存の平文行をサーバーで E2E 化するときは「端末が sealed box で鍵を預ける → 退避 → CAS 変換 → 確認 → 別 CLI で削除」の 5 段に分け、退避だけ鍵なしで切替直後に置く
category: pattern
tags: [e2e, migration, sealed-box, cas, cli, retention, orphan-sweep]
created: 2026-10-16
project: global
sources:
  - projects/bloom/.designs/20261016-plaintext-post-migration.md (R2)
  - projects/bloom/.designs/20261015-e2e-location-and-media.md §10 / §14-2 / §15-8
---

## Context

bloom 0.2.3 で、切替 migration が平文投稿とビーコンの場所を全削除する設計 (T3 / T4) を「サーバーがグループ鍵を一時的に預かって E2E 形式に変換し、平文は別置きで保全、確認とバックアップの後に削除」に置換した。運営が移行中に読めることを許容する裁定 (身内運用) が前提。R1 (作者の端末が媒体を取り直して再アップロード + 30 日期限) は同日に破棄された。

## What

- **鍵の受け渡し**: `GET …/keys` の応答に `plain_migration: {public_key, epoch, key_id} | null` を足し、端末は鍵同期の中で最新 epoch の鍵を移行用 X25519 公開鍵宛ての sealed box にして 1 リクエスト送る。サーバーは env の seed (`SeedKeyPair`) から導く秘密鍵で開く。生の鍵は DB に置かず、sealed のまま 1 グループ 1 行。env を外せば DB の sealed は誰にも開けない
- **付与鍵の検証**: 同じグループの既存の暗号文 (`dek_wrap` / `place_ct`) を 1 つ `Open` して合わなければ 422 で保存しない。無ければ `verified=false` で保存し、変換時に再検証
- **退避 (stash)** は鍵なしで走る第 1 段: 平文ファイルを掃除ツールが走査しない `legacy/<元のディレクトリ>/` に rename し、行の参照列 (`video_path` と `plain_video_path`) を両方そこへ向ける。閲覧は平文のまま動く。これで DB を見ない purge を切替直後 (旧クライアントが流入する前) に安全に回せる
- **変換**は 1 行 1 tx の CAS (`WHERE media_e2e=false`)、tx の第 1 文でグループの共有 advisory lock → 最新 epoch の key_id 一致 → `SELECT FOR UPDATE` → UPDATE → `tmp/` から最終パスへ rename → commit。`media_id = 行の id`、ファイル名も行の id
- **孤児掃除の窓**を構造で閉じる: (a) 参照集合を `legacy/` の twin で閉包する (rename は mtime を保つので mtime 猶予では守れない)、(b) 作成 1 時間以内のファイルは孤児にしない (rename → commit の ms の窓)
- **削除**は別 CLI で、変換済み行だけ (`media_e2e=true AND plain_* IS NOT NULL`)。未変換の行と `legacy/` は触らない。期限なし
- 確認手段は変換 CLI の `-dry-run` の件数 (未退避 / 退避済み未変換 / 待ちグループの内訳)

## Why

- サーバーが鍵を預かれるなら、端末の転送・upload 機構の分岐・期限処理が全部要らない。暗号部分は既存の `Seal` / contexts / `E2EStoragePaths` で済む (devseed の投稿組み立てが雛形)
- 「平文を消さない」と「DB を見ない purge」は、purge が走査しないディレクトリへ退避しないと両立しない。purge に DB 参照の keep を足す案は 2 ループに穴を作りやすい (R1 で Codex に BLOCKER)
- 行 id を保てば CASCADE / SET NULL の参照 (リアクション・コメント・通知タブ・動画リクエスト) が無傷で残る

## How to apply

- 「既存行をサーバーが暗号化し直す」要望は、(1) 鍵の預け口 (sealed box + 検証)、(2) 鍵なしの退避段、(3) CAS 変換、(4) 掃除ツール 2 種 (DB 非参照の purge / DB 参照の sweep) の窓、(5) 削除 CLI、の 5 点を必ず表にする
- 「削除」を「残す」に反転するときは `count = 0` を固定しているテスト・`retainedPlainTables` 型の集合・手順書の文字列を固定しているテストを grep して置換表に載せる
- Go で封じた行を端末の実デコーダが開ける KAT (fixture を Go のテストが書き出し、Dart のテストが実 `PostDecoder` で開く) を必須試験に入れる
