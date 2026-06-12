---
title: オンボーディング完了判定は単一の純粋関数に集約する (二重定義はデッドロックを生む)
category: pattern
tags: [architecture, authorization, guard, onboarding, single-source-of-truth, hono, tanstack-router, deadlock]
created: 2026-06-12
project: atender
sources: [".designs/20260612-setup-deadlock-fix.md", "apps/api/src/middleware/setupGuard.ts", "apps/web/src/router.tsx"]
---

## Context
atender 本番で「新規ユーザーが Setup から抜け出せないデッドロック」が発生。
「セットアップ完了」を判定する箇所が 2 つあり、条件が食い違っていた:
- フロント router ガード (`requireCompleteSetup` → `me.setupStatus.isComplete`):
  `schoolId && departmentId && defaultSemesterId` (timetable 不問)
- API ミドルウェア (`setupGuard`, `GET /api/today` 等が使用):
  上記 + `hasUserTimetable` (timetable 必須)

## What
2 基準のズレが構造的ループを生む:
1. Setup 完了は timetable を作らない (学期作成だけ) → router の `isComplete=true` で Home を通す
2. Home が API を叩く → `setupGuard` が timetable 無しで 403 SETUP_REQUIRED
3. フロントの 403 ハンドラが Setup に送還 → 戻る → ループ
timetable を作る唯一の導線が「Home 到達後」にしか無いため、新規ユーザーは
永久に到達できない = デッドロック。1 機能 (v9 オンボーディング) リリース時から
潜在し、無関係な後続変更では露見しなかった (完了 fixture が常に timetable 込みだった)。

## Why
「完了」の定義が 2 箇所にインラインで重複コピーされ、片方だけ条件が増えた。
ガードA (router) とガードB (API middleware) は本来「同じ問い (setup 済か?)」に
答えるべきなのに、別々の式を持つと**片方が通して片方が弾く中間状態**が生まれる。
その中間状態に「次へ進む導線」が無いと閉じ込められる。
認可/オンボーディングの段階ゲートは、フロントとバックで二重に書かれがちで
(UX のため先回りで弾く + サーバで本当に弾く)、同期がズレると事故る典型。

## How to apply
- **完了判定は 1 つの純粋関数に集約する**。フロント・バックの全ガードがそれを参照:
  ```ts
  // apps/api/src/lib/setupStatus.ts
  export function isSetupComplete(u: {schoolId,departmentId,defaultSemesterId}): boolean
  ```
  `me.ts` の `isComplete` も `setupGuard` も同じ関数を呼ぶ。条件式を 2 度書かない。
- **統一する方向は「ゆるい側」**。段階ゲートは「次の段階に進む前提リソースを、
  そのゲートの先で作る」構造になりがち。前提を完了要件に含めると、それを作る画面に
  到達できず詰む (鶏と卵)。今回は timetable を完了要件から外し、Home 到達後に作らせた。
- **真に必須なリソースは「それを使う操作」の直前で個別にガードする**。
  atender は出欠記録 service が `findActiveUserTimetable` null で個別に 403 を投げる
  二重ガードを持つ。「オンボーディングゲート (学校/学科/学期)」と「操作前提ガード
  (timetable)」を分離し、前者を緩く・後者を操作単位で。
- **Architect チェックリスト**: 段階ゲートを設計するとき「この完了判定は他に何箇所で
  評価されるか」を grep し、全箇所が同一ロジックか確認する。フロント先回りガードと
  サーバガードがある機能は特に。
- **Reviewer チェックリスト**: 完了 fixture が「最大構成 (全リソース込み)」しか無いと、
  中間状態 (一部だけ完了) のデッドロックを取りこぼす。「完了だが後続リソース未作成」の
  fixture を必ず 1 つ作り、各ガードが一致して通す/弾くかをテストする。
