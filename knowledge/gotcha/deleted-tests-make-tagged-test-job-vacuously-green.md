---
title: コンパイルできなくなったテストを削除すると、build tag 付きの CI job は「中身ゼロで緑」になる
category: gotcha
tags: [go, build-tags, ci, integration-test, vacuous-pass, reviewer]
created: 2026-07-30
project: omatase
sources:
  - "omatase 再構成 基盤編 (2026-07-30) / .designs/20260730-rebuild-foundation.md"
  - "knowledge/gotcha/fake-store-tests-miss-db-constraint-drift.md"
---

## Context

破壊的な再構成 (DB スキーマ + 認証 + API 契約を同時に差し替える) を実装した commit で、
コンパイルが通らなくなった integration テスト 4 ファイル (計 2981 行) が削除された。
CI には `go test -tags integration ./internal/store/... ./internal/http/...` を回す
専用 job があり、`deploy` は `needs: [ci, integration, docker-build]` で守られていた。

## What

削除の結果、この job は

```
?   github.com/omatase/backend/internal/store   [no test files]
?   github.com/omatase/backend/internal/http    [no test files]
exit 0
```

を返すようになった。**テスト 0 本で exit 0 = 緑**。`deploy` のゲートは形だけ残り、
実質は無条件通過になる。

同型の事故がこの PJ には既にあり (`fake-store-tests-miss-db-constraint-drift.md`:
DB の CHECK と REST の許容値が割れたまま両方緑)、その教訓のために作られた層が
**削除によって無効化された**。危険なのは:

- **失敗が 1 件も出ないので、レビューでもログでも異常に見えない**
- `-tags integration` 付きのファイルは通常の `go build` / `go vet` / `go test ./...` から
  見えないので、**コンパイルが壊れていること自体が普段の CI に出ない**
  (= 実装者が「壊れた → 消す」を選ぶ動機が構造的に生まれる)
- 「テスト件数」を台帳に持っていない PJ では、前後比較で気付く手段が無い

## Why

Go の `go test` は対象パッケージにテストが 1 本も無い場合、それを失敗ではなく
`[no test files]` として報告して exit 0 する。「テストが 0 本」と「テストが全部 pass」を
終了コードで区別できない。build tag で隔離されたテストは、そのタグを付けたときだけ
コンパイルされるため、タグ無しの日常ビルドが赤くならず腐りやすい。

## How to apply

- **Reviewer は召集時に、まずテスト本数のゼロを確認する。** 判定の前に
  `go test -tags <tag> ./... 2>&1 | grep "no test files"` を 1 回撃つ。
  ヒットしたパッケージが設計 doc の「テスト基盤」節に名指しされていたら、
  そこは vacuous であって GREEN ではない
- **CI 側に下限を敷く。** `go test -tags integration -v ./... | grep -c "^--- PASS"` が
  期待本数を下回ったら落とす、または `-run '.*'` で 0 件を検出する step を足す。
  「緑」ではなく「N 本走って緑」を成功条件にする
- **削除された旧テストは `git show <base>:<path>` で読める。配管だけ流用する。**
  test-DB の truncate/seed、自前 EC 鍵 + ローカル JWKS サーバー、httptest の組み方は
  再構成後も使える。**アサーションは流用しない** — 旧契約を固定したものなので、
  再構成後の設計では「間違い」を固定してしまう
- **破壊的変更の設計 doc には「既存 integration テストをどう作り直すか」を書かせる。**
  「テストを書かない Developer」+「コンパイルが壊れる破壊的変更」の組み合わせは、
  黙って削除に流れる。設計時に Reviewer の担当範囲として明記すれば削除が事故として見える
