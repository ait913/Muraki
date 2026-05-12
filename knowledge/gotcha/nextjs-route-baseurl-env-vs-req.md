---
title: Next.js route の baseUrl は req URL ではなく env 変数 (PUBLIC_BASE_URL) 由来
category: gotcha
tags: [nextjs, route-handler, baseurl, reviewer, vcard]
created: 2026-05-10
project: meishilink-mvp
sources: ["meishilink-mvp Phase 4 vcard-route-photo テスト失敗"]
---

## Context

vcard route handler が `PHOTO;VALUE=URI:` に絶対 URL を埋め込む。Reviewer のテストで `new Request("https://example.com/yamada/vcard")` を渡し、レスポンスに `https://example.com/u/yamada/logo` が含まれることを期待したが、実際は `http://localhost:3000/u/yamada/logo` が返った。

## What

実装は `process.env.PUBLIC_BASE_URL ?? "http://localhost:3000"` を baseUrl に使い、req URL の origin は無視する。

理由:
- vCard はメール / AirDrop で送る前提で、req URL の origin (リバプロ等で変動) より固定の本番 URL を使う方が安定
- 設計doc §3.F の `${baseUrl}/u/${card.handle}/logo` の baseUrl は **env 変数を意味する**。req URL ベースとは書かれていない
- Reviewer がこの暗黙前提を読み落とすと「設計違反 (RED)」と誤判定する

## Why

vCard は long-lived な artifact (ユーザーのアドレス帳に保存される)。req URL ベースで埋め込むと:
- preview 環境で生成した vCard が prod URL に解決されない
- リバプロ後段でホスト書き換えがあると壊れる

env 由来なら deploy 単位で URL が固定され、artifact の長期可搬性が保たれる。

## How to apply

Reviewer が route テストで「絶対 URL を含む文字列」を assert するときは:

1. テスト先頭で `process.env.PUBLIC_BASE_URL` を **明示的に set / unset**
2. assert は `process.env.PUBLIC_BASE_URL ?? "http://localhost:3000"` を期待値に組み込む
3. req URL を変えても assert に影響しないよう、`https://example.com` 等の host を request URL に使うが期待値には反映しない

```ts
beforeAll(() => {
  delete process.env.PUBLIC_BASE_URL;
});

it("...", async () => {
  const text = await response.text();
  expect(text).toContain("PHOTO;VALUE=URI:http://localhost:3000/u/yamada/logo");
});
```

または beforeAll で `process.env.PUBLIC_BASE_URL = "https://test.example"` を set し期待値も合わせる。

**Architect 向け**: 設計doc に `baseUrl` を出すときは「`process.env.X ?? <fallback>` の形で env 由来」と明記する。Reviewer の解釈余地を消す。
