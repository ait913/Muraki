---
title: 端末暗号化バッチ同期 — 決定的 blob_id と per-key Keychain item の keyring
category: pattern
tags: [e2ee, idempotency, keychain, icloud-keychain, flutter_secure_storage, sodium, batch-upload, aead]
created: 2026-10-03
project: global
sources:
  - projects/bloom/.designs/20261003-track-blob-encryption.md (§2-2 D2/D3, §4-2〜4-8)
  - ~/.pub-cache flutter_secure_storage_darwin-0.4.0 FlutterSecureStorage.swift baseQuery/readAll
  - scratchpad KAT (sodium 4.1.1+2 と cryptography 2.9.0 で XChaCha20-Poly1305 の出力一致を実走)
---

## Context

bloom で本人の位置ログを端末暗号化してサーバーに不透明 blob として置く設計 (E2E Phase A)。要件は「drift の schema を変えない」「鍵は iCloud Keychain 同期のみ・ローテーション無し」「失敗時は次の契機で再送」。

## What

1. **再送の冪等は blob を永続化せず、blob_id を中身から決定的に、かつ秘密鍵付きで導出して取る**。副鍵 `idKey = HMAC-SHA256(暗号鍵, "<用途>.blobid.v1" ‖ 0x01)` (HKDF-Expand 1 ブロックと同形) → `HMAC-SHA256(idKey, 正規化平文)` の先頭 16 byte を UUID (version 8 / RFC 4122 variant) にする。最頻の失敗「サーバーは保存したが応答が消えた」で次回は同じ点集合 → 同じ id → サーバーが `duplicate` を返す。点集合が変わったときだけ内容が一部重複し、復元側の自然キー判定が吸収する。nonce は乱数のままで良い。**鍵なしの公開ハッシュ (例: `sha256(key_id + 端末連番 + 時刻)`) にすると、key_id が公開なのでサーバーが平文候補を総当たり照合できる** (bloom R0 で Codex が cid=8,686 を復元してみせた)
2. **点の同一性に端末ローカルの連番 (AUTOINCREMENT id) を使わない**。別端末・再インストール直後の点が別地点でも同じ番号になり、復元の `INSERT OR IGNORE` で消える。記録の性質から一意になる自然キー (例: 秒精度の記録時刻 + 取得種別。記録側のスロットルで同一端末内の衝突が無いことを確認する) で照合し、ローカル id は復元時に振り直す
3. **鍵は「1 本 = 1 Keychain item (account に key_id を含む)」の keyring にし、「現行鍵」は created_at 最古 (同時刻は key_id 昇順)**。単一 account に鍵を置くと、iCloud 同期が届く前に新端末が鍵を生成した場合に同期で片方が上書きされ、その鍵で封じた blob が永久に読めなくなる。item を分ければ両方残り、全端末が同じ現行鍵に収束する
4. **復元は鍵を生成せず、done フラグで打ち切らない**。ユーザー別の `after_seq` カーソルで増分取得し (他端末の後発 blob を拾うため)、手元に無い key_id の blob は skip して seq 範囲を kv に残す。後から keyring にその key_id が現れたら (同期の遅着) その範囲だけ取り直す
5. **AEAD の AAD に「封筒ヘッダ (version + key_id) ‖ 用途文字列 ‖ 0x00 ‖ user_id ‖ blob_id」**を入れる。サーバーが blob を別ユーザー・別 id に付け替えると復号が失敗する
6. 封筒はバイナリ (version 1 + key_id 16 + nonce 24 + ct‖tag)。HTTP では JSON の base64 フィールド、DB は bytea。将来の動画 (数百 KB) で base64 の +33% を保存しない
7. `flutter_secure_storage` の iOS は `accountName` が `kSecAttrService`、`accessibility` と `synchronizable` が**読み取りクエリの一致条件にも入る**。同期鍵用 (`first_unlock` + `synchronizable: true`) と既存の端末限定 item (`first_unlock_this_device`) は別 service の別インスタンスにし、1 インスタンス内で options を混ぜない

## Why

- 永続化して同 id 再送する方式は送信待ちテーブル (= schema 変更) が要る。決定的 id なら「どの点を送ったか」は既存の `synced` フラグだけで済む
- iCloud Keychain の競合解決はアプリから制御できない。上書きされ得る形を作らないのが唯一の防御
- 鍵が後から届くのは E2E の通常ケース (新端末の初回起動直後)。復元を 1 回で完了扱いにすると永久に取りこぼす

## How to apply

- 端末で暗号化してサーバーに置くバッチ同期を設計するときは、まず「再送時に同じ id を作れるか」を考える。作れるなら送信キューを持たない
- 端末共通 DB にユーザーの記録を溜める設計では、鍵をユーザー別にするだけでは足りない。ローカルデータに所有者を持たせ、別ユーザーのサインインで wipe、送信・復元は認証世代を送信前・応答後・DB 書込前に検査する
- 鍵の保管は「単一 account の上書き」になっていないかを確認し、同期ストレージなら per-key item にする
- 既知解答ベクトル (固定 key/nonce の封筒 sha256) を設計 doc に載せ、2 実装 (例: libsodium と純 Dart) で一致を実走しておくと、バックエンド差し替え時の互換テストがそのまま使える
