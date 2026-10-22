---
title: 共有 venv 1 本で動く複数サービスを破壊的な版へ上げるときの切替 — 最終名で venv を作り symlink で切替、書き込みを閉じた検証窓、コミット点以後は前進修正
category: pattern
project: global
tags: [deploy, venv, systemd, gunicorn, migration, rollback, sqlite, nginx, nexom]
created: 2026-10-22
sources:
  - Muraki/projects/aisaba-platform/.designs/20261022-nexom-120-migration.md §3, §9, §11
  - Codex リリース前レビュー第 1 パス (同 doc への NO-GO 9 MUST、2026-10-22)
---

## Context

aisaba_platform は 7 サービス (systemd `nexom@<svc>`、gunicorn) が **1 本の venv** を共有し、`ExecStart` が `services/venv/bin/gunicorn` 固定。フレームワーク (Nexom 1.1.41 → 1.2.0) が破壊的で、起動時に SQLite スキーマを自動移行する。アプリコードも新版専用になる (旧版では import できない)。コンテナ化はしない制約。初版の設計は Codex に 9 MUST で NO-GO を受け、下記はその修正後の形。

## What

1. **venv は最終名で作る (`venv-1.2.0`)、切替は `venv` symlink の向きで行う**。console script (`bin/gunicorn`, `bin/pip`) の shebang は作成時の絶対パスで固定されるので、`venv.new` に作って `mv venv.new venv` すると shebang が消えた場所を指して全サービスが起動不能になる — しかも `venv/bin/python -c "import …"` の検査は通るので気付けない。旧実ディレクトリは `venv-1.1.41` に改名し、旧 shebang (`services/venv/bin/python3`) は symlink が旧に向いている間だけ正しく解決する = ロールバックは symlink を向け直すだけ。unit は不変。`pip` は常に `<venv>/bin/python -m pip`
2. **準備は対象コミットに固定する**: `git fetch` だけして `git show TARGET:services/requirements.txt` (pin 済み) で venv を作る。設定の新版は現行を複製して差分を当て、`python -m py_compile` と grep で検査した状態で置いておき、停止窓では `cp` だけ
3. **ローリング再起動を選ばない**。旧プロセスは `sys.path` の `venv/...` を見続け、symlink を差し替えた瞬間から旧コードの遅延 import (multipart / Pillow) が新版を読む窓ができる。import 検査 (各 `wsgi.py` の import = テンプレート検証・設定キー・起動時移行) も稼働中には流せない (本番 DB が移行されて旧プロセスと齟齬)。**全停止 → バックアップ → 切替 → import 検査 → 起動** の一括窓
4. **書き込みを閉じた検証窓を作り、コミット点を明示する**。nginx の対象 vhost だけに追跡 include (`gateway/includes/maintenance.conf`、中身は `include /etc/nginx/<app>-maintenance/*.conf;` の 1 行、0 件一致は合法) を足し、保守 ON = リポジトリ外の状態ファイルに `if ($http_x_maintenance != "<鍵>") { return 503; }` を書いて reload、OFF = 消して reload (cloudflared 経由は全部 loopback から来るので `remote_addr` では区別できず、ヘッダ鍵で検証要求だけ通す)。**追跡 include は http 文脈の glob (`include gateway/*.conf`) に掛からないサブディレクトリに置く** (`if` は server / location 専用で、glob に拾われると `nginx -t` が落ちる)。**状態は追跡ファイルに持たない** (ON/OFF の内容差が未コミット変更になり `git checkout` が拒否される)。構造の検査は `git archive TARGET gateway` を一時ディレクトリに展開し絶対パスを `sed` で書き換えた最小 `nginx.conf` で `nginx -t -c` を ON / OFF 両方。チェックリスト全合格 → 状態ファイル削除 + reload = コミット点。**コミット点までは完全復元、以後は前進修正のみ** — 再開後の新規行・削除された実体はバックアップ復元で巻き戻せない (私有 DB と中央 DB の整合が崩れる)
5. **バックアップはサービスユーザーで取る** (`sudo -u www-data python -c sqlite3.backup`)。root で作ると `cp -a` 復元で root 所有になりサービスが書けない。復元後に `stat` と `sudo -u www-data test -w` で確認
6. **gitignore されたコードを追跡化する切替のロールバック順**: 旧コミットへ `git checkout` を **先に** (追跡化したファイルが消える) → 退避ディレクトリを戻す → 設定を戻す。逆順だと checkout が復元物を消すか拒否する
7. **共有 nginx include を触る前に `grep -l` で include 元を全部数える**。aisaba の `security_headers.conf` は 9 vhost (非 Nexom の Coolify / appily / opendoc を含む) が使っていた。対象サービス専用の include を新設して vhost 側を差し替える
8. 設定の新キーは wsgi が必須 import (fallback 既定値なし)。漏れは import 検査で `ImportError` として止まる
10. **手順を書く前に `stat` で所有者を取り、各コマンドの実行ユーザーを決める**。aisaba はコード木が `ais:www-aiss`、`data/` だけ `www-data` で、`sudo -u www-data git …` は全部 `Permission denied` になるはずだった。**private repo + 資格情報の無いサーバー** には `git fetch` が無い: Leader が `git push ssh://<host>/<repo> <sha>:refs/heads/release/<slug>` で別 ref に届け (チェックアウト中ブランチ宛ては `receive.denyCurrentBranch` で拒否)、サーバーで `rev-parse` を突き合わせて checkout する
9. 起動順は「混在窓が無いなら依存される側から」。移行ガイドの「クライアント先・サーバー後」は rolling 時の互換規則

## Why

- 共有 venv では「サービス単位の段階移行」が物理的に無い。切替の原子性は symlink の向きでしか作れない
- 「壊れたら戻す」の戻し先が 3 つ (コード・ライブラリ・DB スキーマ) に割れているうえ、再開後の書き込みは第 4 の状態。設計 doc の時点でコミット点を切っておかないと「データ損失なし」が嘘になる
- import 検査は最も安い「起動するか」の確認だが、起動時移行を持つ FW では副作用がある。副作用を許容できる場所 (停止窓の中、バックアップ後) に置く

## How to apply

- 破壊的 FW 更新の設計 doc には「切替単位 / 順序 / import 検査の位置 / バックアップ対象と所有者 / 検証窓の作り方とチェックリスト / コミット点 / 復元の 4 点と順序 / 各段の戻り先表」を §方針と §デプロイ手順の両方に書く
- venv 切替を書く前に `head -1 <venv>/bin/gunicorn` で shebang を見る。絶対パスなら rename 方式は使えない
- テストで FW の DB 層を別スレッドから叩く設計を書く前に `grep check_same_thread` する。無ければ in-process 共有は不可で、サブプロセスにする
