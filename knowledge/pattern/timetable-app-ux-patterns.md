---
title: 時間割アプリ UX パターン (Penmark 系 / 学生向け / 2024-2026)
category: pattern
project: global
tags: [timetable, ui, ux, mobile-first, japanese-student-apps, bottom-sheet, grid]
created: 2026-05-15
sources:
  - https://penmark.jp/news/2024/07/04/v3-0-0/
  - https://penmark.jp/guide/
  - https://penmark.jp/news/2023/12/11/ios17-widget/
  - https://help.penmark.jp/hc/ja/articles/4711177136153
  - https://www.appbank.net/2024/04/10/iphone-application/2740924.php
  - https://good-apps.jp/articles/890/
  - https://www.notion.so/calendar
  - https://flexibits.com/fantastical
  - https://www.nngroup.com/articles/bottom-sheet/
  - https://www.nngroup.com/articles/mobile-ux-tap-swipe/
---

## Context

日本市場で学生向け時間割アプリを設計するとき、Penmark (日本最大級・大学生 100 万人超ユーザー) を主参考に、海外カレンダーアプリ (Notion Calendar / Fantastical) の連続イベント表現と組み合わせるベストプラクティス。Atender (Muraki) redesign の調査で抽出。

## What

### 1. ナビゲーション (bottom tab 5 個)

学生向けアプリは bottom tab 5 個が標準。Penmark v3 (2024-07) は `時間割 / カレンダー / トーク / 掲示板 / マイページ`。Studyplus は `タイムライン / 勉強記録 / 分析 / コミュニティ / マイページ`。共通項:

- **アイコン + ラベル両方**
- マイページが必ず右端
- 「主機能」が左端 (時間割 / タイムライン)
- 5 個固定。これより増やすと「More」格納が必要

### 2. 時間割エディタ (グリッド)

- 行 = 時限、列 = 曜日
- セル tap → 詳細表示 (Penmark は別画面遷移、2024-2026 トレンドは **bottom sheet** に短縮)
- **空きセル tap → 追加 / 入っているセル tap → 詳細 + 編集削除** が直感的
- 連続コマは **`grid-row: span N` のカード + 内部分割線消去** で merge 表現 (Notion Calendar / Outlook 流)
- カード: 淡い背景塗り + 左 4px の濃い accent border + 開始-終了時刻フル表示

### 3. 時限可変 (1-12 限)

Penmark は最大 12 限まで対応。固定 5 限ハードコードは不可。
- 設定 UI: 時間割画面右上歯車 → bottom sheet で時限数 +/- + 各時限の開始終了時刻を 1 分単位編集
- 学校テンプレが標準時刻を提供 (取り込み済テンプレからデフォルト復元可)

### 4. ワンタッチ出欠

- 今日の授業カード上に `[出][欠][遅]` (3 文字単漢字) ボタン
- 1 tap で記録、トースト + undo で誤操作復旧
- iOS interactive widget も用意できると最強 (Penmark 2023-12 対応)

### 5. 編集削除導線

- 主導線: **セル tap → bottom sheet 詳細 → 編集 / 削除ボタン** (NN/g 推奨、発見性高・安全)
- 補助: 長押し → 即削除確認 dialog (パワーユーザー向け、誤操作リスク低めのため undo 付き)
- 不採用: スワイプ削除 (グリッドではスクロール競合)、3 点リーダー (時間割セルでノイズ)、インライン編集 (閲覧 vs 編集の意図不明瞭)

### 6. 連続コマ表現

| 流派 | 例 | 採用基準 |
|---|---|---|
| セル merge (`grid-row: span N`) | Notion Calendar / Penmark | ★ 標準。1 つの背景塗り + 左 border |
| カード重ね (absolute) | Google Calendar / Cron | 時間刻みが分単位で柔軟なカレンダー向け、時限固定の時間割には過剰 |
| 同色セル 2 個 (境界線残る) | 旧来の HTML テーブル | ✗ 連続感が出ない |

時刻表示: 連続コマ全体の `09:00 - 12:10` を 1 行で出す (Fantastical 流)。

## Why

- 日本学生市場のデファクトが Penmark で 100 万人ユーザー (2024-05)、命名・操作感を踏襲することで学習コストゼロ
- bottom sheet は 2024-2026 のモーダル代替トレンド、コンテキスト維持 + スワイプ閉じが直感的 (NN/g)
- 連続コマ merge は視覚的に「1 つの授業」と即理解できる、分割線残しは別授業に見える誤認リスク
- 時限可変は専門学校 (8 限) / 高校 (6 限) / 大学 (4-5 限) で全部違うため固定不可

## How to apply

新規時間割アプリ・Atender redesign で:

1. **ナビは bottom tab 5 個** から逸脱しない (3-5 推奨範囲)
2. **空きセル tap = 追加 / 入セル tap = 詳細** の 2 動詞で全部済む UI に統一
3. 連続コマは **CSS Grid `grid-row: span N` の 1 カード**で描画、内部 border は消す
4. 時限可変 UI は MVP 必須項目に入れる (見落とし注意 ★ schema 対応済でも UI 漏れあり)
5. 出欠は `出 / 欠 / 遅` の 3 文字漢字、ワンタップ + undo
6. 編集削除は **bottom sheet 詳細経由を主、長押しを副** に明確化

逆に**やらない**:
- ハンバーガーメニュー (発見性低)
- スワイプ削除 (グリッド競合)
- 3 点リーダー (時間割セルのノイズ)
- アニメ調キャラ・派手アクセント (学生向けでも node-utility 系は落ち着いた配色がふさわしい)

## 反例 / 限界

- Penmark は「セル tap → 別画面遷移」だが、bottom sheet 化が現代的でモーション軽量。ただし詳細情報が大量にあるケース (シラバス全文等) では別画面遷移の方が適切
- 連続コマ merge は曜日列幅が極端に狭いモバイル (≤320px) で文字省略 (`-webkit-line-clamp`) が必須、長い授業名 (例: 「線形代数学Ⅰ演習」) は 2 行で切る
- bottom tab 5 個は PC では sidebar 化推奨、tab を上部 nav に持ち上げると視線移動が大きい
