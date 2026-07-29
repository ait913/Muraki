---
title: interface fake だけのハンドラテストは DB 制約との食い違いを検出しない
category: gotcha
project: omatase
tags: [testing, database, migration, integration-test]
created: 2026-07-29
sources: [omatase 2026-07-29 統合作業で実際に発生]
---

## Context

DB 依存を避けるため、REST ハンドラのテストを `Store` interface の fake 実装に対して回すのは定石で、速くて安定する。omatase もその方針で、`internal/http` のテスト全部が fake store 相手だった。

ところが**「migration を変える人」と「API のバリデーションを書く人」が別ブランチで進む**と、この構成は破綻を検出できない。

## What

実際に起きたこと:

- ブランチ A (API): `POST /messages` が `message_type` を `message|emoji|stamp|announcement` の 4 種で受理。
- ブランチ B (migration): `messages_type_check` を `message|announcement` の 2 種に絞る CHECK を追加。
- **両ブランチのテストは両方とも緑**。fake store は CHECK 制約を持たないので、`emoji` を渡しても素通りする。
- マージしても **git は衝突を報告しない** (ファイルが別)。**コンパイルも通る** (どちらも string)。
- 壊れるのは実 DB に繋いだ最初の 1 回目。`emoji` を投稿した瞬間に 500。

同じ形の罠: `NOT NULL` 追加 vs API の nullable 許容、文字数上限 (`length(btrim(body)) > 0` や varchar(n)) vs API のバリデーション上限、enum 追加漏れ、FK の `on delete` 挙動。

## Why

fake は「呼ばれた/返す」を模すだけで、**DB が持っている宣言的な制約を模さない**。制約は SQL 側にしか書かれておらず、Go の型にも interface にも現れないので、型検査もテストも通ってしまう。

「テストが緑」の意味が **「ハンドラのロジックが仕様どおり」** であって **「保存できる」** ではない、という区別が効いていない。

## How to apply

- **fake store テストを疎通の根拠にしない**。緑は「認可とロジックが仕様どおり」までしか言っていない。
- 実 DB を当てる薄い層を必ず 1 枚持つ。Go なら `//go:build integration` タグで隔離し、migration を当てた Postgres (ローカル `supabase start` / testcontainers) に対して**各 endpoint の正常系を 1 本ずつ**通すだけでも、この種の drift は全部落ちる。CI で DB を立てられなくても、常時緑のロジックテストとは分離できるので台帳は汚れない。
- **DB 制約を変える migration を書いたら、その制約を作る/使う API 側の検証コードを同じ PR で grep する**。制約は 2 箇所 (SQL と API) に重複して書かれる宿命なので、**片方だけ動かさない**とコメントで明示しておく。
- 制約値 (文字数上限など) は、**両側のコードに「相手の場所」をコメントで書く**。omatase では `validateMessageBody` に「上限 2000 は messages_body_required CHECK と封筒仕様に合わせた値。片方だけ動かさないこと」と残した。

関連: [[non-optional-dto-field-is-not-additive-for-callers]]
