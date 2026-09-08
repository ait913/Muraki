---
title: 週パターンから生成した occurrence 表に「日付単位の例外 (振替・置き換え)」を足す標準形
category: pattern
project: global
tags: [attendance, occurrence, schedule, transfer, prisma, sqlite, schema-design, regeneration]
created: 2026-09-08
sources:
  - Muraki/projects/atender/.designs/20260908-build18-rooms-reschedule-export.md §4
  - apps/api/src/services/occurrenceGen.ts / meeting.service.ts (atender)
model-era: opus-5.1
---

## Context

時間割アプリのように「週パターン (Meeting: 曜日 × 時限) から学期分の occurrence 行を事前生成し、読み取りは occurrence を date でフィルタするだけ」という構成に、**パターンに無い日付だけの授業** (台風の振替、学期末の補講) を足したい場面。occurrence の FK は必須で、パターン編集時は `deleteMany → 全再生成` している。

## What

occurrence 表の形は変えず、**例外を「パターン行を指したまま日付が曜日と一致しない occurrence」として同じ表に置く**。触るのは生成・再生成・再調整の 3 箇所だけで、読み取り側は無傷。

1. **例外ヘッダ表** `Transfer { id, timetableId, date, kind, meta… }` と、occurrence への nullable FK `transferId` + 写し先の値の snapshot (`periodIndex`) を追加 (additive)
2. **unique key の名前空間分離**: `@@unique([meetingId, date, periodOffset])` を壊さないため、例外行の `periodOffset` を `BASE(1000) + 絶対時限` にする。通常行 (0…N−1) と衝突せず「同じ授業が同じ日に通常 + 例外」も表せる
3. **再生成の除外**: パターン編集の `deleteMany({ meetingId })` に `transferId: null` を足す。学期日付変更の掃除 (範囲外削除) も同様
4. **置き換え (displacement) は生成側で解く**: 例外が通常授業と同じ時限に重なるとき、通常行を消して `Displacement { meetingId, date }` を残し、**生成関数がその (meeting, date) をスキップ**する。読み取りにフラグ分岐を足さない。粒度は Meeting 単位 (時限単位だと連続コマが半分残る)
5. **読み取りが行から導出している値を洗う**: `periodIndex = meeting.start + offset` のような導出は例外行で嘘になる → `row.periodIndex ?? 導出` に置換 (箇所数は grep で確定)
6. **クライアント側でパターン展開している画面**は自動反映されない → その loader だけ occurrence 範囲 API を追加で読み、`excluding: Set<"meetingId|date">` で置き換え分を落とし、例外行を別イベントとして足す

## Why

- 別テーブル / nullable FK / フラグ列は、読み取り N 経路すべてに union か分岐を強いる (漏れる)。生成側 3 箇所に閉じる方が安全
- 置き換えを `CourseSuspension(courseId, date)` で表すと、同じ科目が週 2 回あるとき振替側まで消える。(meetingId, date) 粒度の専用行が要る
- SQLite の Prisma migration は FK 列追加でテーブル再定義 SQL を出すが、`INSERT INTO new_ SELECT` でデータは保持される (破壊的ではない)。目視確認とデプロイ前バックアップで足りる

## How to apply

- 設計時に「読み取り経路 × (行が入るか / 導出値が正しいか / occurrence を読んでいるか)」の表を先に作る (`knowledge/role/architect.md` #23)
- 例外の削除は「ヘッダ削除 (cascade) → 置き換えていた meeting をその日だけ再生成」の 2 手で元に戻る。出欠記録付きの削除は cascade で消えるので UI で確認を挟む
- 例外の日付は学期日付の再調整で消さない (ユーザーが明示的に置いたもの)
