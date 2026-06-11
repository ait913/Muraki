---
title: 出席率の3指標分解 — 「今日まで実績 / 楽観射影 / あとN回休める」標準計算パターン
category: pattern
project: global
tags: [attendance, stats, denominator, projection, occurrence, ux]
created: 2026-06-11
updated: 2026-06-11
sources:
  - Atender .designs/20260611-semester-redesign.md
  - Atender .designs/20260611-semester-fixes.md
  - Atender .designs/20260611-occurrence-based-denominator.md
  - Atender .designs/20260611-date-input-and-allowed-days.md
  - Atender apps/api/src/services/attendanceStats.ts
---

## Context

出欠管理アプリで「学期全体の予定回数」を分母にすると、学期序盤は未来分が分母に入って率が不当に低く出る。ユーザーが本当に知りたいのは (1) 今日までの実績率と (2) あと何回休めるか。

## What

occurrence (実日付に展開された授業実体) を 3 クラスに分けて集計する:

- **fixed**: 記録あり → ルール重み (num, den)。REDUCE_DENOMINATOR/CANCELLED は den=0、SEPARATE は両方除外
- **floating past**: date <= today かつ記録なし (= 未記録)
- **floating future**: date > today かつ記録なし。休講日は全クラスから除外

3 指標:

1. **今日まで率** = 過去分の Σnum / Σden。**過去未記録 (floating past) は分母に入れて分子に入れない = 欠席扱い**。未記録は件数バナー/バッジで強めに別出しし、記録を促す
2. **射影** projectedNum/Den = fixed 全期間 + floating **future** を出席仮定。**floating past (過去未記録) は分母にだけ残し分子から外す** (= 欠席扱い、楽観射影しない)
3. **あと N 回休める** = `floor((1 − r) × D − 消化済み欠席 + 1e-9)` (r = 必要出席率)。**D = 学期全体の有効授業数 = occurrence 実数ベース** (`course.occurrences.length − denominatorReduction`、休講/SEPARATE/REDUCE を除外)。**消化済み欠席 = 記録済みの欠席相当重み** (ABSENT=1.0, HALF_PRESENT[遅刻/早退]=0.5, PRESENT=0)。未記録は消化に数えない (=学期全体視点の楽観値)

### ★「あと N 回休める」は学期全体ベース・「率」は今日まで — 別物 (2026-06-11 tweaks)

ユーザーのメンタルモデルは2指標で**母数も未記録の扱いも別**:
- **率 (出席率)** = 今日まで実績。未記録=欠席 (上記1)。「今のところの達成度」
- **あと N 回休める** = 学期全体で許される総欠席枠 − 消化済み欠席。**「今学期トータルで3回休める授業、すでに2回休んだ → あと1回」というカウントダウン**。未記録は枠を消費しない (楽観)
- 実装: `allowedAbsences = floor((1−r)×D − (fixedDenAll − fixedNumAll) + 1e-9)`。`D = denominator = course.occurrences.length − denominatorReduction`(occurrence実数ベース)、消化欠席=`fixedDenAll − fixedNumAll`(記録済みのみ集計=未記録を構造的に除外)
- ★**母数 D は occurrence 実数ベースに統一する** (2026-06-11 occurrence-based-denominator)。`totalSessions`(ユーザー手入力・デフォ15)ベースだと occurrence 実態と乖離 (水曜2限×4日=8コマでも15固定で「あと4限休める」と甘く出る)。`D = occurrences.length − denominatorReduction` は `fixedDenAll + floatingPast + floatingFuture`(旧 projectedDen)と恒等的に一致 (occurrences.length = suspended+fixed件数+floatingPast+floatingFuture、denominatorReduction = suspended+separate+reduceDen)。全期間率・今日まで率・あと N 回の母数がすべて occurrence 実数で揃う。totalSessions は概念ごと不要になり Course/TemplateCourse から物理削除した
- ★**`denominator − numerator` を消化欠席に使ってはいけない** — numerator は記録済み分子だが denominator は totalSessions ベースで未記録分も含むため、差分に未記録が混入する。必ず「記録済みのみの den−num」(`fixedDenAll − fixedNumAll`) を使う
- overall は floor 非線形なので科目別 `(1−r)×D − 消化欠席` の**生値を合算してから floor**

### ★方針転換の経緯 (2026-06-11、redesign → fixes → tweaks)

初版 (redesign) は「過去未記録も出席仮定 (率からは除外)」だったが、**ユーザーは「未記録は出席扱いするな・欠席として扱え」と要求**。fixes で上記へ反転:
- 過去未記録は **今日まで率の分母にも射影の分母にも入り、分子には入らない** (= 欠席と同じ寄与)。記録忘れがあると率が下がり allowedAbsences が保守的になる = 正直側に倒す
- 未来未記録 (floating future) だけは出席仮定のまま (「残りを出席する前提であと何回休めるか」が問いの意味なので未来は楽観で対称)
- 「未記録は率から除外して暴落を防ぐ」という初版の親切心は、**未記録を強く可視化して記録を促す UX** に置換 (率を歪めるより、記録させる動線で解く)
- **さらに tweaks で「あと N 回」を射影ベース (`floor(projectedNum − r×projectedDen)`) から学期全体ベース (`floor((1−r)×D − 消化欠席)`) に変更**。射影式は「未記録も欠席消費」で枠が小さく出てユーザーの「3回休める授業で2回休んだらあと1回」の直感とズレた。学期全体ベースは消化欠席のみ引くので直感に一致

## Why

- 「今日まで」は実施日が要るので申告回数 (totalSessions) ベースでは原理的に計算不能。occurrence ベース一択
- 未記録の扱いを率 (除外) と射影 (出席仮定) で分けるのがミソ: 射影は「未来は出席する」仮定と対称で一貫し、率は確定情報のみで正直
- 必要出席率は Int % (例 70) で持つ。Float 0.7 は floor 境界 (ちょうど 70% で N が 1 ズレる) を二進誤差で狂わせる。epsilon 1e-9 併用
- 全体値の「あと N 回」は科目別 floor の和ではなく**射影を合算してから floor** (floor の非線形性)

## How to apply

- HALF_PRESENT 等で分子が 0.5 刻みになっても floor が端数を吸収するので式はそのまま
- 未来日に事前記録があれば fixed 扱い (floating から外す)
- 過去未記録の符号に注意: 今日まで率の分母 `toDateDen += floatingPast`、射影の分子 `projectedNum` には floatingPast を**足さない** (分母 `projectedDen` には足す)。初版から反転した点なので、改修時は両方の式を必ず確認
- DTO は既存の学期全体率フィールドを壊さず `toDate` / `remainingCount` / `allowedAbsences` を追加する形が安全 (他画面の後方互換)
- UI 分岐: N<0「残り全部出席しても届かない」/ N>=残り回数「全休でも維持」/ それ以外「あと N 回休める」

### ★「あとN限」→「あとN日」への日数換算 (2026-06-11 date-input-and-allowed-days)

コマ単位の `allowedAbsences` (限) に加え「あと何日休める」を併記する場合、**保守的に「1日の時限数が最も多い曜日」で割る**:
- `maxDayPeriods` = 科目の各 dayOfWeek ごとの `Σ periodCount` の**最大値** (同曜日は合算、Meeting 無しは 0)
- `allowedAbsenceDays = floor(allowedAbsences / maxDayPeriods)`
- 異時限 (水2限・金4限) は max=4 で割る = 「どの曜日を休んでも保証される最低日数」。avg/min は実際の消費とズレて保証にならない (min は楽観的すぎ枠切れ、avg は休む曜日次第で超過)
- エッジ: `allowedAbsences == null` (母数0) → days=null / `maxDayPeriods === 0` (Meeting無し、ゼロ除算回避) → null / `allowedAbsences < 0` (下回る見込み) → null (日数非表示、限側の負値文言に従属) / `allowedAbsences == 0` → 0日
- **全体 (overall) には日数を出さない**: 科目ごとに 1 日の時限数が違い、休む日と科目の対応が無いため合算する基準が崩壊する。日数は科目別のみ、overall は「あとN限」のまま
- DTO は `maxDayPeriods:Int` (非null) と `allowedAbsenceDays:Int|null` の 2 つを科目 DTO に持たせる。max を持たせると days の独立検算と「1日◯限」表示拡張が server 改修なしで可能

### ★date/time input のモバイル幅はみ出し (WebKit Bug 136041、2026-06-11)

iOS Safari 17 系は `<input type="date">`/`type="time"` を `inline-flex` 扱いし `width:100%` を無視 → intrinsic 幅でコンテナをはみ出す (iOS18+ は修正済)。**グローバル CSS 1 ルールで全 date/time input 一括修正**:
```css
input[type="date"], input[type="time"] { display:block; min-width:0; max-width:100%; box-sizing:border-box; }
input[type="date"]::-webkit-date-and-time-value { text-align:left; }  /* block 化で中央寄せになる副作用を打ち消し */
```
個別 className より `styles.css` のグローバルセレクタが最小・確実 (date/time を使う全箇所が共通 Input 経由でも漏れない)。PC では元から width:100% が効くので見た目不変、収まっている input にも無害。**jsdom では検証不能** (`::-webkit-*` 疑似要素も inline-flex 固有挙動も非評価) → 自動テスト対象外にし実機目視で確認する旨を Reviewer に明記
