---
title: 位置情報×小グループ SNS の KPI 設計 (指標・プライバシー下限・集計方式・診断パラメータ検証)
category: pattern
tags: [kpi, retention, analytics, location-privacy, k-anonymity, differential-privacy, bloom, character-calibration, postgres]
created: 2026-10-10
project: bloom
sources:
  - https://andrewchen.com/power-user-curve/
  - https://arxiv.org/pdf/2004.04145
  - https://pmc.ncbi.nlm.nih.gov/articles/PMC4569739
  - https://pmc.ncbi.nlm.nih.gov/articles/PMC3607247
  - https://www.postgresql.org/docs/current/functions-datetime.html
  - https://man.archlinux.org/man/REFRESH_MATERIALIZED_VIEW.7.en
---

## Context
Bloom (3〜8 人の固定グループ向け位置情報 SNS、コア = 投稿 + ビーコン) の管理画面 KPI 設計前調査 (2026-10-10)。サーバーが持つデータは「精密軌跡 = 端末暗号化 blob」「footprints = res9 日次ヒット数 (平文・ユーザー紐付き)」「beacons.lat/lng 平文」「monthly_characters.axes に月次の実測スカラー全部」。

## What
- **アクティブ定義は「コア行動の有無」にする。** 位置アプリはバックグラウンドで footprints / track blob / token refresh が走るので、「サーバーに何か届いた日 = アクティブ」にすると全員が毎日アクティブになる。コア行動 = 投稿 / ビーコン作成 / ビーコン承諾 / リアクション / コメント。各々が既存表 (`posts`, `beacons`, `beacon_responses`, `post_reactions`, `post_comments`) の timestamptz から遡及計算できる。アプリ起動は現状どのテーブルにも残らない (`sessions` は refresh 時に INSERT されるだけで `last_used_at` は更新されない — BG refresh で汚れる)。
- Power User Curve (L30 / L7) = 「月 (週) のうち何日アクティブだったか」のユーザー数ヒストグラム。DAU/MAU は 1 つの数字に潰れて分散が見えない (Chen)。Bloom は週 1 リズム (ビーコン) なので **L7 と W1/W4 リテンション** を主、DAU/MAU は参考。
- 小グループ SNS の公開指標は薄い。Life360 は個人 MAU に加え**グループ単位の Paying Circles** を公式指標にしている (定義: 期末に課金済みのサブスクを持つメンバー集合)。Facebook の「10 日で友達 7 人」は活性化の先行指標を探した例 (Chamath の講演由来、数字は FB 固有で流用不可)。Snap / BeReal / Zenly のグループ単位指標の公開情報は見つからなかった (Zenly は MAU 35〜40M 規模の数字のみ)。
- 移動パターンの学術標準: 回転半径 r_g (訪問頻度加重の重心からの距離) と k-radius (上位 k 地点のみの r_g)。Pappalardo 2015 は r_g と r_g^(k) の比で returner / explorer に二分 (k=2 が例、home/work)。比の閾値と k の厳密式は本文が画像で未確認。Bloom の「新規セル比」軸はこの二分法の近似。
- 位置の匿名性: 時間別アンテナ粒度で 4 点あれば 95% が一意 (de Montjoye 2013)。**粗くしても効きが弱い** (解像度の約 1/10 乗でしか下がらない)。Bloom の footprints (res9 日次セル集合) は個人を特定できる粒度なので、管理画面に per-user セル集合を出さない。
- Google の移動レポートの公開基準 (巨大 N 前提): Laplace ノイズ (件数 ε=0.11/0.22、1 日 1 ユーザー最大 4 組に寄与を制限、合計 ε=0.44〜1.76)、ノイズ後件数 < 100 は非表示 + 3km² 未満の領域は統合。Bloom の規模 (数十〜数千人) では同じ基準は満たせない。
- 日付境界: `timestamptz AT TIME ZONE 'Asia/Tokyo'` は timestamp (tz なし) を返す → `::date` で JST 日付。**`footprints.publish_day` は 21:00 JST 区切りの「公開日」でカレンダー日ではない**。DAU 等のカレンダー日 KPI と混ぜない。
- Postgres マテビューは `REFRESH` で内容を全置換 (増分更新なし、CONCURRENTLY は読み取りを止めないだけで再計算は全量)。

## Why
- コア = 投稿 + ビーコンなので、活動度はコア行動で測るのが意図に沿う。起動基準は「位置アプリの背景活動」と「閲覧だけの日」を区別できない。
- 管理側集計でも PRODUCT.md §7 (順位付け・遅刻可視化・既読・ノルマ・陣取り) に抵触しない形にする必要がある (ランキング表・個人の遅刻・投稿ごとの閲覧ログを作らない)。

## How to apply
(Bloom 設計時の推奨。詳細な KPI 表は Leader への報告に添付)
1. **二層のアクティブ**: `Active(core)` = コア行動のある JST 日 (遡及計算可)。`Visit` = 起動日 (新設: 認証済み API のホーム取得で `kpi_user_day(user_id, day)` に UPSERT 1 行、内容は持たない)。リテンション・L7 は Active(core) で、Visit はコア行動の前段 (見るだけの人) の可視化に使う。footprints / track blob / refresh は活動に数えない。
2. **集計**: 21:00 バッチ (既存 `runGroupParams` と同じ位置、`batch_runs` の冪等キー) に `runKPIRollup` を足し、前日 JST 完全日の凍結集計を `kpi_daily` (日付 PK、user_id なし) に UPSERT。直近 3 日は再計算して遅延到着を吸収。コホート表 `kpi_cohort(cohort_week, week_n, size, active)` もコホート確定後は凍結 → **退会は `users` CASCADE で行が消えるので、遡及再計算するとコホートが縮み、リテンションが水増しされる**。退会数は user_id なしのカウンタで別に持つ。マテビューより「バッチで INSERT する履歴表」(`group_params` と同じ流儀)。数千ユーザーまでは Postgres で足りる (DuckDB は一次ソース未確認、必要性は判断のみ: 10^5 ユーザー超か footprints の自由探索が要る時)。
3. **プライバシー下限** (k=5 / 分位は N≥20 は慣行ベースの設計値で出典なし):
   - 位置派生の指標は per-user 表示ゼロ。API は集計行のみ返し、user_id は集計 SQL の外に出さない
   - ビン / グループ集合の人数 < 5 は「<5」で非表示。合計と部分和の差分で逆算できるなら補完側も隠す (固定ビンのみ公開)
   - 分位 (p10〜p90) は母集団 N≥20 から。グループ単位の集約は 5 グループ以上かつ 20 人以上
   - 地図系は res7 以下の粗さ + 5 グループ以上。res9 や beacons.place_name の個別表示はしない
   - 順位表・「下位グループ」リスト・個人の遅刻・投稿ごとの閲覧ログを作らない (§7)。リスク群は件数のみ
   - 差分プライバシーは既定採用しない (運営者 = データ管理者で DB に直接触れる。外部公開する数字を出す時だけ Laplace、寄与上限付き)
   - 運営者が被験者を知っている小 N では k 匿名でも守れない → N<20 の間は位置分布を画面に出さず、診断パラメータの検証は devseed の合成データか個人を含まないスカラー分位だけで行う
4. **診断パラメータ検証は新規データ不要**: `monthly_characters.axes` に days / diff_median_min / radius_p80_m / explore_ratio / initiated / joined / arrival_on_time / arrival_total / new_cells / total_cells が全て保存されている。閾値 (定数: T ≤5 分, W ≥3000 m, E ≥0.20, L = initiated ≥ joined) を変えた what-if は SQL だけで再現できる (`type_code IS NOT NULL` の行のみ = 14 日以上記録した月)。見るもの: 軸ごとの正側比率 (目安 25〜75%、設計上の目安で出典なし) / 閾値 ±20% 内の人の割合 (月跨ぎでキャラが揺れやすい帯) / 軸間相関 / 16 (+ `-` を含む 36) タイプの実測 vs 独立仮定の期待値 / 月次の同タイプ継続率 / 時間軸・集合軸の nil 率。
   - 未出現タイプの判定は N 依存: 出現率 p のタイプを 95% で 1 件以上見るのに N ≥ ln(0.05)/ln(1-p) (p=2% → 149 人、p=6.25% → 46 人)。同一グループ内は相関するので有効 N はグループ数寄り。
   - 実装上の疑い (要実測): (a) `explore_ratio` は「月初以前に一度も出ていないセル」比なので、記録開始から 1 か月目のユーザーは全セルが新規 = 100% で必ず E → 記録開始からの経過月で層別する (b) `radius_p80_m` は hits で重みづけた重心からの距離だがパーセンタイルは**セル数ベース (hits 重みなし)** で、移動中に補間されたセルも数える → 電車通勤が半径を押し上げる可能性 (c) 時間軸は `arrived - starts_at` を 0 でクリップし starts_at 無しは除外 → 「今から集合」型で starts_at が作成時刻に近いと遅刻でなく移動時間を測る (d) L/F は `initiated >= joined`、Σjoined = (平均承諾者数) × Σinitiated の恒等式から、ビーコンの平均承諾者が 1 人以上なら多数派が F になりやすい。
