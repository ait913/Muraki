---
title: Touri 流の「シンプル + 並列拡張」設計パターン
category: pattern
tags: [design, architecture, schema, simplicity, extensibility, ceez7, moneylog]
created: 2026-05-10
project: global
sources:
  - /Users/touri/Desktop/ceez7 bin/ceez7/main/index.py
  - /Users/touri/Desktop/ceez7 bin/ceez7/app/index.py
  - /Users/touri/Desktop/ceez7 bin/ceez7/app/moneylog/index.py
  - /Users/touri/Desktop/ceez7 bin/ceez7/app/moneylog/common/app/v1_117/js/app.js
---

## Context

ユーザー (Touri Aida) が CGI 時代から積み上げてきたコードベース (ceez7 / マネログ) を読んで抽出した設計パターン。本人いわく「**目的に対してなるべくシンプルな実装と、汎用性・拡張性に長けた設計**」。AI コードはほぼ含まれていない、純度の高い設計筋肉のサンプル。マネログの「収入/支出を並列に追加できる構造」を本人が代表例として挙げた。

## What

### 1. 並列拡張可能なデータ形 (Uniform Shape + Discriminator)

マネログの records は **すべて同じ形** で保存される:

```js
{
  record_id, type, paid, category_id, tag_id,
  date, discription, amount
}
```

- **`type` フィールドが収入/支出/その他を区別する** — 別テーブルにしない
- 新しい記録種別 (例: 投資・送金・節約目標) を追加したくなったら **`type` の取り得る値を増やすだけ**
- スキーマ変更不要、UI 側でアイコン色を `p-ml__display__month__records__record__icon__${type}` のように type 名をクラスサフィックスに混ぜて派生

settings 側も flat dict で拡張容易:
```js
{
  "config":     { ... },
  "categories": { id: { name } },
  "tags":       { id: { category_id, name, color } }
}
```

### 2. ceez7 main の Articles / Works も同じ思想

`main/index.py` で Articles と Works は **構造もループも対称**:

```python
item = pathlib.Path(contents_dir).glob('*')        # Articles
item = pathlib.Path(works_data).glob('*')          # Works
# ↓ どちらも同じ処理
item_n = natsorted(item, reverse=True)
for i in item_n[:N]:
    with open(f"{dir}/{i.name}/config.json") as d:
        config = json.load(d)
    # config から f-string で HTML 組む
```

- **コンテンツの種類を増やすことが「ディレクトリツリーをもう一本生やすこと」と等価**
- 各 item は独立ディレクトリ + `config.json`、スキーマは緩く拡張可能
- 一覧 / ランキング / おすすめ も同じループの抽象 (slice 範囲・並べ替えキーが違うだけ)

### 3. ファイルシステム as DB

- 記事 (article) → `/<id>/config.json` + `/storage/`
- 作品 (works) → `/<id>/config.json` + `/work.webp`
- マネログのバージョン (v1_10, v1_112, v1_117 ...) → ディレクトリ単位で並列保存、Git 不要で履歴を残せる

### 4. CGI / 直接出力スタイル

- `print("Content-Type: text/html; charset=utf-8\n")` を最初に出す
- `os.environ.get('HTTP_COOKIE')` で cookie 読む
- HTML は f-string で組む (テンプレートエンジン不使用、共通部分だけ `webrender` ラップ)
- フレームワーク層は薄い: `cweb` (auth/render) + `ceez7webModule` (apps 共通)

### 5. サブアプリ = ディレクトリ + index.py

- `ceez7/app/<subapp>/index.py` が CGI エンドポイント
- 共通モジュールは `/ais/service/ceez7/cmodule` や `/ais/service/app` にあり、`sys.path.append` で読み込む
- nginx が `/<subapp>/` を該当 index.py にマップ

## Why

- **CGI 時代から自力でなぞってきた歴史**: フレームワークが提供する抽象を使わず、自分で必要な抽象だけを切り出す思想
- **DB スキーマを切り直すコスト >> JSON フィールドを足すコスト**: 個人開発で「あとで仕様が変わる前提」だと、緩い形のほうが結果的に開発速度が上がる
- **「種類を増やす」がコピーで済む**: ディレクトリをもう一本掘る・type 値を一つ足す、で機能拡張完了。Touri の「汎用性・拡張性に長けた設計」の正体はこれ
- **既存フレームワークだと逆に窮屈**: ORM や型に縛られると、この緩さが失われる。だから自前の薄いラッパに留めている

## How to apply

新規データモデルや機能を Touri に提案するとき、以下を default で考える:

- **テーブル/型を「種類」ごとに分けない**。type / kind / discriminator フィールドで対応できないか先に検討
- **共通 shape + 差分は config フィールド** (JSON / dict) で表現
- **ディレクトリ並列が自然な領域では FS as DB を許容** (記事・作品・コンテンツなど読み中心の場面)
- **ループの抽象を再利用** — 一覧/ランキング/おすすめが同じソート + slice + render なら DRY する
- **テンプレートエンジン強要しない** — f-string や軽い文字列組み立てで足りる場面では足す価値ない
- **バージョン管理は Git 前提**だが、ユーザーは旧来「ディレクトリコピーでバージョン保持」もしてた背景を理解しておく (古いコードを移行する依頼が来た時、その慣習を尊重)

逆にこの哲学を**やぶる**提案 (テーブル分割・厳格スキーマ・重いテンプレ) をする場合は、明確な理由 (本番運用で壊れる・パフォーマンス etc.) を添えること。

## 反例 / 限界

- 件数が大きくなるとファイルベース DB は遅い (ranking 計算で全 config.json を舐めている — `main/index.py:127-137` 参照)。本格 DB が要る規模になったら型を切る判断は必要
- type discriminator は **N 種類が多くなると enum/union 型管理が辛くなる**。3〜10 種類ぐらいまでが快適ゾーン
- スキーマレスな緩さは、**他の開発者** (Codex 等の AI 含む) には推測しづらい。設計 doc 側で明示するか、TypeScript でも `type` フィールドの union を定義しておくと事故が減る

## ceez7 コードベースの世代分布 (2026-05-10 時点)

**世代1: CGI 直書き (~1000 行)** — `account/dash/articles/index.py` (835行) / `main/app/bin/money/index.py` (1067行) / `drive/index.py` (338行)
- 全ロジック1ファイル、状態機械の自作 markdown parser、shutil で FS 操作
- リスク: f-string で HTML を組むため **XSS**、`requests.get(任意URL)` で **SSRF**、`cgitb.enable()` 本番有効でスタックトレース漏洩

**世代2: 過渡期 (旧 cweb)** (200-500 行) — `main/index.py`、`drive/index.py`
- 共通部 (`webheader`/`webauth`/`webrender`) を `/ais/service/ceez7/cmodule` に切り出し
- HTML はまだ各 index.py で f-string

**世代3: モダン (ceez7web/ceez7applications)** (50-120 行) — `app/*` 全ファイル、`main/auth/index.py`
- `main()` + try/except + 統一エラー型 (`ceez7app.G_ERROR`) + OpenID 風 SSO
- HTML 生成は `w_render.template1()/template2()` に閉じ込め
- 自前FW: `ceez7web.web_module()` API は `loginmode() / access_user / ex_query() / reload_display() / set_cookie() / web_openid()` 等

## 触る時の判断基準

- **app/ への追加実装** → 世代3パターン (`main()` + `try-except` + `w_render`) を踏襲。安全
- **main/ の変更** → ハイブリッド状態。どっちのスタックで書かれてるか先に見る
- **account/ や drive/ の機能追加** → **可能ならリライト提案**を出す。1ファイル800-1000行のままパッチを当てると XSS/SSRF が増える
- **新規サブアプリ** → `app/<name>/index.py` で世代3スタイル、これがコスト最小
