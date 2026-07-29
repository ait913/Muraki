---
title: NEXT_PUBLIC_* は runtime env では届かない (Dockerfile ARG + build-time 指定の両方が要る)
category: gotcha
project: omatase
tags: [nextjs, docker, coolify, env, build-time]
created: 2026-07-29
sources: [omatase 2026-07-29 本番実測 (deploy log + client chunk grep)]
---

## Context

Next.js の `NEXT_PUBLIC_*` は **ビルド時に client bundle へ文字列として焼き込まれる**。PaaS (Coolify 等) の env 画面に登録しただけでは、それは *runtime* env なので client には届かない。

omatase では `apps/web/src/lib/config.ts` が `process.env.NEXT_PUBLIC_API_BASE ?? ""` を読んでおり、未設定のままビルドすると **空文字が焼き込まれ、fetch が相対 URL になって自ドメインに飛ぶ** (症状: API 呼び出しが軒並み 404、しかもビルドもデプロイも成功する)。

## What

**3 つ全部が揃って初めて値が届く**:

1. `Dockerfile` の builder stage に `ARG NEXT_PUBLIC_X` と `ENV NEXT_PUBLIC_X=$NEXT_PUBLIC_X`
2. PaaS 側で「build-time env」として指定 (Coolify なら env の `is_buildtime: true`)
3. `next build` がその stage で走ること

Coolify は build-time 指定された env を、**生成した Dockerfile の先頭に `ARG KEY=value` を注入した上で `docker build --build-arg KEY` を付ける**。実測ログ:

```
ARG NEXT_PUBLIC_API_BASE=https://omatase-api.n-wasabi.org
...
docker build --no-cache ... --build-arg NEXT_PUBLIC_API_BASE --build-arg NEXT_PUBLIC_WS_BASE ...
```

## Why

runtime env は `docker run -e` 相当で、既にビルド済みの JS ファイルの中身を書き換えられない。server component からは `process.env` が runtime でも読めるため、**「サーバー側では動くのにブラウザだけ壊れる」**という非対称な壊れ方をする。これが原因特定を遅らせる。

## How to apply

- **検証は env 一覧でなく成果物 (bundle) を grep する**。env が正しく登録されていることは何の証拠にもならない:

```sh
curl -sS -o page.html https://<app>/<値を使うページ>
for u in $(grep -o '/_next/static/chunks/[a-zA-Z0-9._-]*\.js' page.html | sort -u); do
  n=$(curl -sS "https://<app>$u" | grep -c "<期待する値>")
  if [ "$n" != "0" ]; then echo "HIT $u"; fi
done
```

- 値を使っていないページの chunk には当然出ない。**その値を実際に使う画面**を選んで叩くこと。
- ビルド時に埋まる = **値を変えたら再ビルドが要る**。env を PATCH しただけでは反映されない。
- 逆に、秘密情報を `NEXT_PUBLIC_` に置くと bundle に永久に焼き込まれて配布される。公開して良い値だけに限る。

関連: [[coolify-https-redirect-loop]] / omatase の `CLAUDE.md`「env を足す」節
