---
title: pnpm 11 は .npmrc の pnpm 固有設定を読まない (設定が黙って死ぬ)
category: gotcha
project: omatase
tags: [pnpm, monorepo, metro, expo, ci, build]
created: 2026-07-29
sources: [omatase 2026-07-29 EAS iOS ビルドが 3 回失敗して特定]
---

## Context

pnpm 11 は `node-linker` などの **pnpm 固有設定を `.npmrc` から `pnpm-workspace.yaml` へ移した**。`.npmrc` に書いた設定は**エラーも警告も出さずに無視される**。

omatase はこれで iOS ビルドが 3 回落ちた。`.npmrc` には `node-linker=hoisted` がちゃんと書いてあり、リポジトリの規約にも「これを外すな」と明記してあったのに、である。

## What

壊れ方が厄介なのは、**ローカルだけ動き続ける**こと。

| | pnpm | `.npmrc` の設定 | node_modules |
|---|---|---|---|
| ローカル | 9.15.0 (Homebrew) | **読む** | hoisted → 動く |
| CI / EAS | 11.13.0 (`packageManager`) | **読まない** | symlink → 壊れる |

この乖離を作っていたのが `.npmrc` のもう 1 行:

```
manage-package-manager-versions=false
```

これがあると、ローカルの pnpm は `package.json#packageManager` に**自動追従しない**。
「決定論的にする」つもりの設定が、**ローカルと CI で別バージョンの pnpm を使う**状態を固定していた。

症状は本題から遠いところに出る。Expo/React Native の場合、Metro が pnpm の symlink レイアウトを解せず:

```
error: Cannot read properties of undefined (reading 'transformFile')
    at Bundler.transformFile (.../node_modules/.pnpm/metro@0.84.4/node_modules/metro/src/Bundler.js:55:30)
```

`.pnpm/` を含むパスが出ているかどうかが唯一の手がかりで、**設定ファイルを見ても異常が無い**ので原因に辿り着きにくい。

## Why

pnpm 側の設計変更 (設定の集約先を `pnpm-workspace.yaml` に統一) に、**移行を促す警告が無い**ため。使う側は「書いてあるから効いている」と信じ続ける。

さらに `node-linker` は**失敗が遅延する**種類の設定で、install は成功し、ビルドの終盤 (バンドル生成) で初めて壊れる。install が通った時点で「依存は正しい」と誤認しやすい。

## How to apply

- **pnpm 11 以降を使うなら、pnpm 固有設定は `pnpm-workspace.yaml` に書く**:

  ```yaml
  packages:
    - "apps/*"
  nodeLinker: hoisted
  ```

- 古い pnpm を使う環境も残るなら**両方に置き、片方に「正典はもう一方」と注記する**。値を変えるときは両方直す。
- **効いているかは設定ファイルでなくコマンドで確かめる**。これが唯一の確実な確認方法:

  ```sh
  pnpm dlx pnpm@<packageManager のバージョン> config get node-linker
  # undefined が返ったら、その設定は読まれていない
  ```

- **`manage-package-manager-versions=false` を疑う**。ローカルと CI で別バージョンの pnpm が走る状態を作る。決定論を狙うなら、むしろ `packageManager` に追従させる方が乖離が減る。
- 症状が出たら **`node_modules/.pnpm/` を含むパスがスタックに出ていないか**を見る。出ていれば hoisted が効いていない。

### EAS のビルドログは brotli

原因特定にはビルドログの実物が要るが、`eas build:list --json` の `logFiles` URL は **brotli 圧縮**で、`curl --compressed` も Python の `gzip`/`zlib` も展開できない (URL は 900 秒で失効する点にも注意)。Node なら読める:

```js
require('zlib').brotliDecompressSync(fs.readFileSync('log.bin'))
```

関連: [[fake-store-tests-miss-db-constraint-drift]] (ローカルで緑・本番で壊れる型の別例)
