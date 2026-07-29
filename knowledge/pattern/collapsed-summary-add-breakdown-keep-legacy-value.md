---
title: 「N件を1値に潰した集計」の拡張は、内訳を additive に足して潰した値を legacy 据え置きにする
category: pattern
project: atender
tags: [dto, additive, enum, zod, swift, api-evolution, calendar, aggregation]
created: 2026-07-29
sources: [".designs/20260729-semester-calendar-multi-status.md", "apps/api/src/services/semesterOverview.service.ts"]
---

## Context

サーバが「1 日 N 件の出欠」「1 リポジトリ N 件の CI 結果」のような **N 件 → 1 値** の畳み込みを
して DTO に載せている。後から「潰さずに全部見せたい」「潰す規則に無い状態 (公欠) を区別したい」
という要望が来る。ネイティブアプリのように**古いクライアントが端末に residual する**構成だと、
DTO の変え方が UI 設計より先に効いてくる。

## What

3 つの選択肢のうち、採るのは 3 番目。

1. **潰した enum に値を足す** (`ALL_PRESENT` に加えて `HAS_EXCUSED`) — ✗
2. **潰した enum を捨てて生配列を返す** (`statuses: Status[]`) — ✗
3. **★ 件数内訳オブジェクトを additive に足し、潰した値は legacy 互換として据え置く** — ○

```ts
AttendanceDaySummary = {
  date: string,
  status: "ALL_PRESENT" | ... ,   // ← legacy 互換。新 UI は読まない。ロジックも変えない
  occurrenceCount: number,
  counts: {                        // ← 追加。severity 順の描画はここだけを読む
    present, absent, excused, tardy, earlyLeave, suspended, unrecorded
  },
}
```

不変条件を 1 本立てる: `sum(counts) === occurrenceCount`。テストの主軸になる。

型付きクライアント (Swift) 側は **Optional** で宣言し、nil = 旧サーバとして
「潰した値からマーク 1 個を導出する legacy 経路」に落とす。

## Why

- **enum 値追加は additive ではない**: 旧クライアントの未知値フォールバック
  (`UnknownFallbackRawRepresentable` → `.unknown` → 無表示) に落ちるので、
  **配布済みビルドの表示を退行させる**。フィールド追加 (旧クライアントは無視するだけ) とは非対称。
- **enum 値追加は組合せ爆発する**: 「欠席+公欠の日」「遅刻+休講の日」で値がまた足りなくなる。
  潰す構造が残る限り要望は解けない。
- **生配列は肥大する**: 1 日 8 コマ × 学期 180 日で最大 1440 要素。クライアントは件数しか使わない。
- **legacy 値を据え置くと既存テストが全部緑のまま残る**: atender では API テスト 4 本
  (`toContain("ALL_PRESENT")` 等) と、`status === "NO_CLASS"` に依存する時間割展開ロジックが無傷だった。
  「壊れるテスト」は設計判断で減らせる。
- **Swift Optional は「新アプリ × 旧 API」の窓を守る**: 非 Optional だと DTO 親ごと decode が throw し、
  画面が丸ごとエラーになる。Optional なら「古いサーバでは今日と同じ描画」に劣化するだけ。
  合成 Codable は `var x = default` の既定値を使わない (missing key は必ず throw) ので、
  「デフォルト値付き非 Optional」という逃げ道は無い。

## How to apply

1. サーバの畳み込み関数 (`classifyDay()` 等) は**触らない**。直上に
   `// legacy 互換フィールド。表示は counts を使う (設計doc §X)` とコメントを置く。
2. 集計関数を 1 本足すだけにする (畳み込みが使っている中間データをそのまま数える)。
   Prisma/DB の変更は通常不要 — 「既存データの読み方」の話だから。
3. クライアントの描画決定は **内訳だけを入力にする純粋関数 1 本**に集約する
   (`dayVisual(summary, isFuture) -> { marks, dashed }`)。潰した値を読むのは legacy 分岐だけ。
4. 表示順 (severity) を配列/`CaseIterable` の**宣言順で定義**し、
   「宣言順 == 期待順」を Web と iOS の両方でアサートする 1 本を置く (二重実装のドリフト検出)。
5. `MIN_IOS_BUILD` を上げない (= 強制アップデート不要) と設計 doc に明記する。
   additive を名乗る根拠 (wire / TS / Swift の 3 層それぞれ) を表で示す。
