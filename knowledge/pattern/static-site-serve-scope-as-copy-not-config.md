---
title: 静的サイトの「配信範囲」は PaaS の設定でなく Dockerfile の COPY で定義する
category: pattern
project: global
tags: [coolify, static, nginx, dockerfile, security, ci, deploy, build-pack]
created: 2026-07-16
sources:
  - Muraki/projects/nwasabi-hp/.designs/20260716-hp-deploy.md  # 本パターンの初出 (build pack 選定)
  - knowledge/library/coolify-static-buildpack.md              # static は COPY . . を生成する (実測)
---

## Context

静的サイト (素の HTML/CSS、ビルド済 SPA 等) を PaaS に載せるとき、
「配信ディレクトリを指定する設定フィールド」が用意されていることが多い
(Coolify の `base_directory`、他 PaaS の publish dir 等)。

一見これが正解に見えるが、**PaaS の既定は「リポジトリを丸ごと配る」**ことがある。
Coolify 4.1.2 の `build_pack: static` は `COPY . .` を生成し、`base_directory: "/"` だと
`README.md` も `.github/workflows/*.yml` も **HTTP 200 で返る** (実測)。**private リポでも配信内容は公開**。

## What

**配信範囲を「PaaS の設定フィールド」でなく「自分で書いた Dockerfile の `COPY`」で定義する。**

```dockerfile
FROM nginx:1.31-alpine
COPY site/ /var/www/site/             # ← これが配信範囲の定義そのもの
COPY nginx.conf /etc/nginx/conf.d/default.conf   # root /var/www/site;
```

配りたいものを `site/` に隔離し、`COPY` でそれだけを入れる。`site/` 以外はイメージに**存在しない**
= HTTP から到達する経路が無い。

### ★ docroot はベースイメージの既定を使わず、自分が所有するディレクトリにする

`nginx:alpine` の既定 docroot (`/usr/share/nginx/html`) には**ベースイメージが `50x.html` / `index.html` を置いている**。
**`COPY` は既存ファイルを消さない**ので、そこへ COPY すると `50x.html` が生き残って配信される (実測 200)。
すると真の配信範囲が **「`site/` ∪ ベースイメージの置き土産」**になり、後者は
**(a) リポジトリを読んでも分からず (b) moving tag (`1.31-alpine` 等) ならコミット無しに変わり得る** —
本パターンが排除したかった性質そのものが裏口から戻る。

**`RUN rm -f .../50x.html` で消すのは減算的で弱い** (ベースイメージが将来何か足せばまた漏れ、また `rm` を足す
追いかけっこになる。しかも足されたことに気づく仕組みが無い)。**docroot 移設は構造的な解**で、
ベースイメージが何を置いても配信範囲は `site/` のまま。

**スモークで固定する**: `expect_404 /50x.html` — docroot が既定に戻る変更が入ったら赤くなる。

### なぜ設定フィールドではダメか

| | PaaS の設定フィールド | Dockerfile の `COPY` |
|---|---|---|
| 定義の在処 | **リポジトリの外** (PaaS の DB) | リポジトリの中 |
| 「何が公開されるか」がリポジトリから読めるか | **読めない** | 読める |
| PR レビューが効くか | **効かない** | 効く |
| git 履歴が残るか | **残らない** | 残る |
| 誰が変えられるか | UI から誰でも (無記録) | commit した人 (記録あり) |
| 壊したときの気づき方 | **無い (黙って全公開)** | CI が赤くなる (下記) |

★ **罠の本体は「事故る」ことでなく「事故が見えない」こと。** 設定を 1 つ消し忘れた/戻した瞬間に
リポジトリ全体が公開され、誰も気づかない。

### ★ 併せて必須: 404 アサート + 破壊テスト

`COPY` で守っただけでは「守れているか」を誰も確認しない。**スモークテストで機械的に検証する**:

```sh
expect_200 /            # 配信されるべきもの
expect_200 /styles.css
expect_404 /README.md   # 配信されてはいけないもの
expect_404 /Dockerfile
expect_404 /.github/workflows/ci.yml
```

このスクリプトを **CI のローカルコンテナと本番 URL の両方**に対して回す (引数は base URL 1 個)。

★ **成立に 2 つの条件がある。どちらを欠いても偽陽性になる**:

1. **200 アサートが 404 アサートの前提。** アプリが落ちている / ルーターが無い状態では
   **全パスが 404** になり、404 群だけを見ると**緑で通る**。「200 が返るものがある」ことを先に確かめる
2. ★ **破壊テストで「404 が COPY の結果である」ことを証明する。** そのファイルが元から無くても 404 は返るので、
   404 が緑なだけでは守りが効いている証拠にならない。**`COPY site/ dst/` を `COPY . dst/` に一時的に広げて
   スモークが赤くなることを 1 度確認する** (Reviewer のタスクにする)

★ **破壊テストのミューテーションは「COPY 先を docroot に向けたまま COPY 元を広げる」(`COPY . dst/`) にする。**
**`COPY . .` を使ってはいけない** — `WORKDIR` を書いていなければ `nginx` 系イメージの `WorkingDir` は **`/`** なので、
ファイルは `/README.md` に落ちて **docroot の外** = 配信されず、**スモークは緑のまま**になる。
これを見て「安全網が壊れている」と誤診しないこと: **漏れていないので捕まえる対象が無い**だけで、
**「漏れるなら捕まる」は成立している** (nwasabi-hp で実測、2026-07-16)。

★ 対比: **Coolify の `static` build pack では `COPY . .` は本当に危険**。あちらは
`WORKDIR /usr/share/nginx/html/` を**先に**吐くので `.` が docroot そのものになる。
**同じ文字列の危険度が `WORKDIR` で反転する** — 「`COPY . .` は危険」と字面で覚えず、
**COPY 先が docroot を向いているか**で判断する。

### 副次的な利点: CI が本番イメージを検証できる

PaaS が Dockerfile を**デプロイ時に生成する**方式 (Coolify の `static` 等) だと、
**CI で焼けるイメージが存在しない**。in-container healthcheck のような本番と同経路の検証を
CI で書こうとすると、PaaS の生成ロジックを CI 側で再現するしかなく、実装ドリフトを抱えた二重管理になる。

自分の Dockerfile なら **CI がビルドしたイメージ = 本番のイメージ**。
「CI 緑のまま初回デプロイだけ落ちる」を塞ぐ step が書ける
([`gotcha/coolify-healthcheck-localhost-ipv6-vs-node-bind.md`](../gotcha/coolify-healthcheck-localhost-ipv6-vs-node-bind.md))。

## Why

- 「Dockerfile を書かない」は**目的ではない**。目的は「push したら出る」であって、
  Dockerfile 3 行の節約と引き換えに (a) 配信範囲の不可視化 (b) CI 検証の不能化 を買うのは取引が悪い
- セキュリティ境界は **version controlled で、レビュー可能で、壊したら赤くなる場所**に置く。
  PaaS の DB のフィールドはその 3 つを全部満たさない
- 同じ構造の一般則: **「相手側の設定で成立させる案」と「自分側で成立させる案」が並んだら後者を採る**
  (omatase の `ENV HOSTNAME=::` vs `health_check_host:"127.0.0.1"` と同型)

## How to apply

静的サイトを PaaS に載せるとき:

1. **配りたいものだけをサブディレクトリ (`site/` 等) に隔離する**
2. **`dockerfile` build pack + `COPY site/ <docroot>/`**。PaaS の「配信ディレクトリ設定」に頼らない
3. **スモークに `expect_404` を書く** (README / Dockerfile / CI 定義 / 設定ファイル)。
   **`expect_200` とセットで**、CI (ローカルコンテナ) と本番の両方に対して回す
4. **破壊テストを 1 度だけ実行する** — `COPY` を広げてスモークが赤くなることを確認。
   これをやっていない 404 アサートは飾り
5. nginx を使うなら `listen 80; listen [::]:80;` で dual-stack にする
   (in-container healthcheck が curl/wget どちらでも通る)

**例外**: ビルドが要る静的サイト (Astro/Vite 等) は `nixpacks`/`railpack` + `is_static: true` +
`publish_directory` が別経路として存在する。ただし配信範囲の可視性は同じ問題を抱えるので、
判断軸は変わらない。

## 関連

- [`library/coolify-static-buildpack.md`](../library/coolify-static-buildpack.md) — `static` が `COPY . .` を生成する実装的根拠、`publish_directory` が無視される罠
- [`gotcha/coolify-healthcheck-localhost-ipv6-vs-node-bind.md`](../gotcha/coolify-healthcheck-localhost-ipv6-vs-node-bind.md) — 自分側を頑健にする vs 相手側で回避する
- [`tool-quirk/coolify-api.md`](../tool-quirk/coolify-api.md) — `base_directory` / `dockerfile_location` の連結規則
