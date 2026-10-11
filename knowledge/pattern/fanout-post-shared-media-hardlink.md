---
title: 1 回のアップロードを N 件の投稿に広げ、メディアはハードリンクで共有する (削除経路の参照カウントを FS に任せる)
category: pattern
tags: [upload, storage, hardlink, fan-out, idempotency, multi-group]
created: 2026-10-11
project: bloom
sources:
  - Muraki/projects/bloom/.designs/20261011-capture-lens-multigroup-segment.md (D8〜D11, §5-3)
---

## Context
bloom で「複数グループに同じ動画を投稿する。投稿はグループごとに別の行だが、ファイルは共有してストレージを増やさない」と裁定された。既存の設計は 1 upload = 1 group = 1 posts 行 = 1 ファイルで、削除経路 (本人削除・管理者削除・離脱・退会・空グループ掃除・孤児掃除・pending 掃除・devseed) が全部「その行のパスを unlink」している。

## What
- 代表の 1 件は既存の経路で作る。追加先は finalize メタの `extra_targets: [{group_id, client_key}]` で受け、代表の投稿ファイルを `os.Link` で行ごとに別名のパスにリンクして INSERT する
- 行ごとにパスが別なので、削除の全経路は無変更で正しい (inode の link count が参照カウントになる)。容量は 1 本分
- `os.Link` が `ErrNotExist` 以外で失敗したら (別ボリューム等) コピーにフォールバックする
- 追加先の client_key は端末が新しく採番する (`UNIQUE (user_id, client_key)` を変えない)。各追加先は client_key で既存を引いてから作るので冪等で、代表を作った直後にプロセスが落ちても再送で埋まる
- 追加先はベストエフォート (非メンバー・上限ならスキップしてログ)。完了の応答形は変えない

## Why
「同じパスを N 行で共有 + 参照カウントで消す」案は、削除の全経路に判定と行ロックを足すことになり、経路の数え漏れがそのままデータ消失になる。ハードリンクなら参照の管理を OS がやる。

## How to apply
- 1 対 1 の資源を N に広げる設計では、先に削除経路を grep で全数表にし、「行ごとに別パス + ハードリンク」で無変更にできるかを確かめる
- 注意点を doc に書く: rsync のバックアップは `-H` が要る / リンクを作ってから INSERT するまでの窓に孤児掃除が走る可能性 (既存の rename → 記録の窓と同じ性質か確認) / E2E 暗号化をグループ鍵で行うと暗号文が投稿先ごとに変わり共有できなくなる (メディアを DEK で 1 回だけ暗号化し、DEK をグループ鍵ごとに包む)
- テストは `os.SameFile` と `Stat_t.Nlink`、片方を消してももう片方が配信できることで確かめる
