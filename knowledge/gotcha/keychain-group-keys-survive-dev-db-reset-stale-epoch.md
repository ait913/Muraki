---
title: Keychain のグループ鍵は dev DB の作り直しを生き残り、同番 epoch の旧鍵が「最新」に選ばれて KEY_EPOCH_STALE が止まらない
category: gotcha
project: bloom
tags: [e2e, keychain, group-key, epoch, devseed, migrate-drop, flutter_secure_storage]
created: 2026-10-17
sources:
  - sessions/2026-10-16-4aab8def.md (項目 78〜79)
  - projects/bloom/app/lib/crypto/group_keys.dart (GroupKeyring.latest)
  - projects/bloom/app/lib/data/env_store.dart (wipeLocalData は k1.* を消さない)
---

## Context

bloom の E2E グループ鍵は Keychain (iCloud 同期、`kBloomSyncedKeychainOptions`) に `k1.<envTag>.group.<gid>.<keyId>` で保存される。owner (user id) はキーに含まれず、サインアウト・接続先切替 (`wipeLocalData`) でも消さない設計 (再インストール後に iCloud から戻すため)。dev の seed グループは ID が固定 (UUIDv5)。

## What

dev3 を `migrate-drop` で作り直し、同じ端末で seed グループに参加し直すと、旧 DB 時代の epoch 1 の鍵と新しい epoch 1 の鍵が同じ gid の下に並ぶ。`GroupKeyring.latest()` は epoch → keyId の文字列順で最後を返すので、旧鍵の keyId が大きいグループでは旧鍵で DEK を包み、サーバー (`checkLocationEpoch`: 最新 epoch の key_id と一致が条件) が `KEY_EPOCH_STALE` 409 を返し続ける。outbox は 60 秒ごとに同じ鍵で再送するので自然には抜けない。サーバー側の DB (epochs / wraps / memberships / key_epoch_required) は完全に整合して見えるのが罠。

## Why

本番では起きない: グループ ID は再利用されず、epoch 番号は単調増加なので、端末に残った鍵がサーバーの最新より上に並ぶことがない。dev の「同じ gid で DB だけ巻き戻す」操作だけが条件を満たす。

## How to apply

- 症状: 投稿が `KEY_EPOCH_STALE` を繰り返す + サーバーの epoch 表が整合 → 端末の旧鍵を疑う。確認は 開発者ツール → E2E 診断 → 「E2E 鍵の状態」の `手元=[1, 1]` (同番が 2 つ)
- 逃げ方 (dev DB 直): `UPDATE groups SET key_epoch_required=(SELECT COALESCE(max(epoch),0)+1 FROM group_key_epochs WHERE group_id=groups.id) WHERE id IN (...)` (`ResetGroupKeys` と同じ文)。端末は次の鍵同期で epoch 2 を作り、`latest()` が新鍵になる。平文移行の grant は旧鍵宛てで `stale` になるので、もう 1 回前景復帰させて付け直す
- 恒久策 (未実装): dev ツールに「この環境のグループ鍵を破棄」を足す (`readAll(prefix: k1Prefix(env,'group'))` → delete)。`wipeLocalData` に含めるのは設計 (k1.* を残す) に反するので別ボタンにする
