---
title: Starlette 1.x + Jinja2 + htmx セルフホスト + hatchling データ同梱
category: library
project: global
tags: [starlette, jinja2, htmx, hatchling, staticfiles, packaging, python]
created: 2026-07-09
sources:
  - .venv/lib/python3.13/site-packages/starlette/templating.py (starlette 1.3.1 実物)
  - https://htmx.org (v2.0.10)
  - npm view htmx.org version → 2.0.10
  - hatchling wheel 実測ビルド (scratchpad/httest)
---

## Context

Python の Starlette アプリに Jinja2 テンプレート + htmx(self-host)で SSR フロントを同居させ、hatchling ビルドで .html/.css/.js を wheel に含めたいとき。SPA を避け MCP サーバー等と同一プロセスに UI を相乗りさせる構成。

## What

### Starlette 1.x の templating / static API (starlette 1.3.1 で実測)
- `from starlette.templating import Jinja2Templates` — **jinja2 は別途 install 必須**(未インストールだと import 時に `ImportError: jinja2 must be installed`)。`starlette>=0.37` を入れても jinja2 は依存に入らない。
- コンストラクタ: `Jinja2Templates(directory=..., context_processors=None)` または `Jinja2Templates(env=jinja2.Environment, ...)`。`directory` は str/PathLike/Sequence 可。
- レンダー: `templates.TemplateResponse(request, name, context=None, status_code=200, headers=None, media_type=None, background=None)`。★ **第1引数が `request`**(旧 `TemplateResponse(name, {"request": request, ...})` シグネチャは非推奨側)。context に request は自動で入る。
- `url_for` は Jinja env に自動注入され、テンプレ内で `{{ url_for('route_name') }}` が使える(request は context 経由)。
- 静的配信: `from starlette.staticfiles import StaticFiles` → `Mount("/static", app=StaticFiles(directory=...), name="static")`。

### htmx セルフホスト
- 最新安定版 = **2.0.10**(2026-07 時点、npm `htmx.org` / htmx.org 公式一致)。min.gz ~16k、依存ゼロ。
- 取得: `npm install htmx.org` → `node_modules/htmx.org/dist/htmx.min.js`、または `https://unpkg.com/htmx.org@2.0.10/dist/htmx.min.js` を落として vendored コミット。CDN 直リンでなく static/ に置いて自前配信。

### hatchling でのデータファイル(.html/.css/.js)同梱 ★実測確定
- `[tool.hatch.build.targets.wheel] packages=["mypkg"]` を設定していれば、**mypkg/ 配下の非 Python ファイル(.html/.css 等)は wheel にデフォルトで同梱される**。setuptools と違い `package-data` / `include-package-data` / `MANIFEST.in` は不要(実測: mypkg/templates/index.html・mypkg/static/app.css が両方 wheel に入った)。
- setuptools の `package-data` 前提はこのバックエンドには当てはまらない。
- 唯一の caveat: hatchling は既定で **VCS(git)追跡ベース**。`.gitignore` された static 資産は wheel から除外される。vendored htmx 等を gitignore する運用なら `[tool.hatch.build] artifacts=["mypkg/static/*.js"]` で拾い直す。git 追跡していれば不要。

### editable install なら packaging は無関係
- `pip install -e .`(editable)で動かすなら、パッケージ dir 内の全ファイルはソースツリーそのままを参照するので wheel 同梱設定に関係なく `Path(__file__).parent / "templates"` で読める。Docker が `COPY <pkg> ./<pkg>` + editable install する構成では、templates/ static/ を pkg 配下に置くだけで runtime に載る。

## Why

- Starlette 1.x で `TemplateResponse` の引数順が request-first に変わっており、古い記事のシグネチャをコピーすると壊れる。実物ソースが正。
- hatchling のデータ同梱は公式 docs が明示しておらず(wheel builder ページも曖昧)、実測が唯一確実。setuptools の知識を持ち込むと誤設定になる。

## How to apply

- 依存に `jinja2` を追加(starlette だけでは入らない)。テンプレは request-first で呼ぶ。
- htmx は `static/htmx.min.js`(v2.0.10)を vendored コミットし `<script src="{{ url_for('static', path='htmx.min.js') }}">` で self-host。
- templates/ static/ はパッケージ dir 配下に置く → hatchling は既定で wheel 同梱、editable install ならなおさら不要設定。git 追跡だけ確認。
