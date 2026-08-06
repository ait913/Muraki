---
title: イベント系アプリの「常設ハブ + ライブカード」IA (時間帯で着地画面を変えない)
category: pattern
project: omatase
tags: [ia, navigation, hub, event-app, live-card, wayfinding]
created: 2026-08-06
sources:
  - Muraki/projects/omatase/.designs/20260806-ui-ia-redesign.md
  - Muraki/knowledge/pattern/ui-ux-design-perspectives.md (§5 wayfinding)
model-era: opus-5
---

## Context

イベント/旅行/待ち合わせ系アプリで「前日は行程を組む画面が主役、当日は今のプランが主役」と
主役が時間帯で入れ替わる。素直に作ると (a) 着地画面を時間帯で切り替える、(b) 進行画面に
編集 UI も同居させる、のどちらかに寄り、(a) は wayfinding (戻るの挙動・現在地感覚) が壊れ、
(b) は最頻画面の認知負荷が上がる。omatase build 8 は行程・メンバー・招待が別画面に散り、
動線の欠け (共有への到達・アナウンスの置き場) が実機レビューで多発した。

## What

- **着地は常に 1 つの「常設ハブ」**: 共有 (上部常設) / アナウンス / プラン一覧 [+] / メンバー /
  チャットをセクションとして 1 画面に集約。タブ bar で割らない
- **時間帯の主役交代は「ライブカード」で表す**: `isLive` (手動 override があるか、現在プランの
  start_time <= now) のときだけハブ上部に L0 のカードが出て、進行ページへ誘導する。
  開始前はカードが無くプラン一覧が主役 — 画面構成は変えず、1 要素の出現だけで主役を切り替える
- 進行ページは別ルートに残す (L0 の孤立・応答 UI 特化)。ハブ ⇄ 進行は 1 タップ往復
- 権限差 (host/member) は同じ画面から host 専用要素を**非描画** (disabled にしない)

## Why

- 着地固定は Jakob's Law / wayfinding に沿う: 「戻る」が常に同じ場所に戻り、現在地が 2 つにならない
- ライブカード条件を純関数 (`isEventLive`) にすると、描画テストなしでも主役交代の規則を検証できる
- 「編集の場 (ハブ)」と「実行の場 (進行)」を分けることで、最頻画面 (当日の進行) に低頻度 UI が
  常駐しない — progressive disclosure の 2 段制限内に収まる

## How to apply

- 判定式は「override != null || currentPlan.start_time != null && start_time <= now」を初期値に。
  時刻を持たない予定しか無い場合は false (一覧が主役のまま) で良い
- モードが複数あるアプリ (即席/計画) では、ハブを持つのは計画モードだけにし、即席モードは
  単画面のまま分岐 1 箇所で振る (即席にハブの空殻を見せない)
- 共有 (招待) はハブ上部に常設する — 「作成直後に配る」が最初のタスクなので、成功後の
  自動共有シート (遷移を止める事故の実績あり) より常設露出が安全
