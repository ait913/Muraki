---
title: moneylog 後継アプリ Pre-design Research (Part A コード考古学 + Part B feasibility)
category: library
project: moneylog-successor (slug 未確定)
tags: [pre-design, moneylog, ceez7, recurring, subscription, balance-prediction, better-auth, hono, drizzle, sqlite, rrule]
created: 2026-06-08
sources:
  - /Users/touri/Desktop/ceez7 bin/ceez7/app/moneylog/common/app/v1_121/js/app.js (live frontend, 3078 lines)
  - /Users/touri/Desktop/ceez7 bin/ceez7/app/moneylog/common/app/v1_121/html/app_display.html (placeholders)
  - https://api.ceez7.com/moneylog/ (API endpoint, backend source NOT available locally)
  - npm registry (npm view, 2026-06-08): 各依存の最新版
  - Muraki/knowledge/pattern/touri-design-philosophy.md (検証対象)
  - Muraki/knowledge/pattern/rrule-string-onfly-expand-with-overrides.md
  - Muraki/knowledge/pattern/calendar-week-pattern-meeting-expansion.md
  - Muraki/knowledge/library/better-auth-hono-drizzle-sqlite.md
  - Muraki/projects/omatase-demo/.knowledge/00-research-summary.md
---

# Part A — moneylog コード考古学

## 0. アーキテクチャ概観 (確定)

- **通信は単一 POST endpoint + `control` ディスクリミネータ**。`https://api.ceez7.com/moneylog/` に `connection(data)` で全リクエストを投げる (`app.js:186-209`)。
  - 全リクエスト body: `{control: "<action>", ...payload}`、`credentials: 'include'`、JSON。
  - 全レスポンス: `{response: "<status>", index: <data>}`。成功時 `response == "Success"`。エラーは文字列で返る (`"FIRST_VISIT"`, `"NOT_LOGINED"`, `"CVERSION_NOT_FAILED"` 等)。
- **認証は ceez7 独自 OpenID SSO** (`NOT_LOGINED` → `https://app.ceez7.com/login/?openid=www.moneylog` リダイレクト, `app.js:3020`)。新アプリでは better-auth に置換。
- **クライアント/サーバ バージョン整合チェック**: `conn_application` に `cliant_version` を送り、サーバが不一致なら `CVERSION_NOT_FAILED` → リロード要求 (`app.js:223,3021`)。
- ★ **着地予測などの計算ロジックは全てサーバ側**。frontend は計算済みの `balance` オブジェクトを受け取って描画するだけ。backend source がローカルに無いため、予測アルゴリズムの内部は **frontend が消費する形状から逆算** したもの (後述、§3)。

## 1. データモデル (確定: frontend 消費形状から)

### record (取引) — `app.js:1216-1224, 1748-1755`
```
{
  record_id,        // サーバ採番。新規は "new" を送る
  category_id,      // settings.categories のキー
  tag_id,           // settings.tags のキー
  discription,      // 概要 (sic: タイポだが原典準拠。bundle 集約キー)
  amount,           // 符号つき数値。収入=正 / 支出=負
  paid,             // 文字列。"paid"==確定、それ以外==未確定(予定)
  date              // "YYYY-MM-DD" 文字列 (new Date(date) でパース)
}
```
- ★ **record 自体に `type` フィールドは無い**。収入/支出は `amount < 0` で render 時に導出 (`app.js:1757-1760, 2308-2311`)。`type` 文字列値は `"inc"` / `"exp"` の 2 値のみが live コードに存在。
- ★ **符号正規化はクライアント側 `proof_text()`** (`app.js:1180-1206`): カテゴリ種別が収入(`"inc"` または id==1)なら金額を正に、支出(`"exp"` または id==2)なら負に強制。**移動(id==4)はここで触らない = 符号フリー**。
- 移動カテゴリ id==4 は task 前提どおりだが、live `proof_text` は 1/2 のみ分岐。移動は別扱い (符号は入力次第)。

### settings — `app.js:211-218` (docstring で明示) + 実消費箇所
```
{
  "config":     {"first_day": int, "case_holiday": bool},
  "categories": {category_id: {"category_name": str}},
  "tags":       {tag_id: {"category_id": str, "tag_name": str, "tag_color": str}}
}
```
- ★ tag は category に属する (`tag.category_id`)。tag が記録の最小分類単位、category はその束ね。
- ★ `tag_color == "$VARIABLE"` は「色未指定」のセンチネル。render 時 `var(--color_c2_text)` にフォールバック (`app.js:1763-1766, 1889-1891, 2067-2071`)。
- `config.first_day` (締め開始日) と `config.case_holiday` (祝日考慮) は settings に存在するが **frontend では一切参照されない**。HTML 上 "開始日=1日" "祝日考慮=しない" は固定表示プレースホルダ (§7)。実際の締め境界計算はサーバ側 (確認不能)。

### pack (月データ) — `control: get_month_data` のレスポンス `index.pack`
```
pack = {
  header: {
    date: "YYYY-MM",
    balance: {
      now:  number,   // 現在の残高 (確定のみ。当月のみ表示)
      last: number,   // 月末に残っている残高 = 着地予測 (未確定込み)
      categorys: { category_id: { all: number, ... } },
      tags:      { tag_id:      { all: number, ... } }
    }
  },
  records: [ record, ... ]   // その月の全 record (paid/未paid 混在)
}
```
参照: `app.js:1973(pack), 2006(balance.last), 2024(balance.now), 2030-2031(categorys.all), 1893-1894/2048(tags.all)`。

### pack_year (年データ) — `control: get_year_data` のレスポンス `index.pack`
```
pack_year = {
  thumbnail: { "<month>": {                       // 月ごと集計 (キーは月)
      balance: number,
      categorys: { category_id: { all: number, apaid_only: number } },
      tags:      { tag_id:      { all: number, apaid_only: number } }
  }},
  records: [ record, ... ]    // 年間全 record
}
```
- ★ **`all` vs `apaid_only` の 2 系列** (`app.js:2579-2580, 2603-2604`): `all` = 未確定込み (=予測)、`apaid_only` (sic, "actual paid only") = 確定のみ (=実績)。これが「予測 vs 実績」の二重集計の核。
- 年の `highlights`/`header` は **frontend が thumbnail から再集計** して作る (`app.js:2561-2683`)。`highlights.monthBalance[12]`, `highlights.categorys[id][12]`, `highlights.tags[id][12]` = 月別推移 (グラフ用)。

## 2. API 契約 (全 control 列挙、確定)

`connection({control, ...})` 呼び出しを全数列挙。**ただし payload/response は frontend 送受信側のみ確認済 (backend 未確認)**。

| control | payload (frontend が送る) | response.index | 行 |
|---|---|---|---|
| `conn_application` | `{cliant_version}` | `{settings, version}` | 221-245 |
| `get_month_data` | `{date:"YYYY-MM"}` | `{pack}` (§1 pack) | 1961-1979 |
| `get_year_data` | `{year}` | `{pack}` (§1 pack_year) | 2542-2559 |
| `dump_record` | `{record_id, category_id, tag_id, discription, amount, paid, date}` (record_id=="new" で新規) | `response=="Success"` | 1212-1229 |
| `delete_record` | `{record_id}` | `"Success"` | 1257 |
| `save_category` | `{category_id, category_name}` (新規/更新兼用) | `"Success"` / `"STILL_IN_USE"` | 1537 |
| `delete_category` | `{category_id}` | `"Success"` / `"STILL_IN_USE"` | 1563 |
| `save_tag` | `{tag_id, category_id, tag_name, tag_color}` | `"Success"` | 1455 |
| `delete_tag` | `{tag_id}` | `"Success"` / `"STILL_IN_USE"` | 1481 |
| `migration` | `{}` | (設定移行) | 949 |
| `initialization` | `{}` | (初期化) | 976 |
| `release_note` | `{}` | `{release_note}` | 1627-1631 |

- `save_*` は **upsert** (新規も更新も同 control、id 有無で分岐はサーバ側)。
- `STILL_IN_USE` = 使用中の category/tag 削除拒否 (`app.js:376`)。**新アプリでも参照整合の削除ガードが要る**。
- ★ **mutation 後の再取得は full re-fetch**: dump/delete 後に `month_display()` or `list_display()` を丸ごと呼び直す (`app.js:1232-1237`)。差分更新なし。TanStack Query の invalidate に素直にマップできる。

## 3. 着地予測アルゴリズム (最重要、ただし★サーバ側=逆算)

frontend が受け取る値の **意味** は確定、計算式は backend 未確認。

- **`balance.now` = 現在の残高** = 確定(paid)レコードのみの累積。当月ビューでのみ表示 (`app.js:2023-2027`)。
- **`balance.last` = 月末に残っている残高(着地予測)** = 確定 + 未確定(その月のもの)を全部足した月末予測値 (`app.js:2002-2007`)。当月なら見出し「月末に残っている残高」、他月なら「月末残高」。
- **月をまたぐ繰り越し**: frontend からは **各月の `balance.last` は独立した値として降ってくる**ように見える (frontend は繰り越し計算をしていない)。繰り越しの累積はサーバ側 (前月末残 → 当月頭残) で閉じている可能性が高いが **確認不能 (不確定事項)**。
- **未確定(`paid != "paid"`)が予測に効く仕組み**: `last` には未確定が入り `now` には入らない。年集計の `all`(未確定込み) vs `apaid_only`(確定のみ) も同じ二系列思想。
- **締めサイクル境界**: `config.first_day` がサーバに存在するが frontend 未使用。HTML は "1日" 固定プレースホルダ。**現行 live は実質「暦月 = 締め月」で動いている可能性が高い** (不確定、要サーバ確認 or 新アプリでは暦月固定で設計)。

★ **新アプリへの最大の含意**: moneylog は「予測ロジックをサーバが隠蔽し、frontend は表示専用」という構造。新アプリでも **予測計算は backend (Hono service 層) に集約** すべき。frontend で残高計算を書かない。

## 4. 概要でまとめる (bundles) — 確定 `app.js:1746-1848`

- `bundle=true` の時、同じ `discription` 文字列の record を集約。
- `record_bundles[discription] = {amount: Σ, records: [...]}`。
- **2 件以上ある discription のみ Bundle 化**、1 件は single 表示 (`app.js:1831-1835`)。
- Bundle は件数昇順ソート (`app.js:1838`)。表示は `"概要 (件数)"` + 合計金額 (`app.js:707`)。
- 月ビュー(`refrection_records`)と年ビュー(`refrection_records_y`)で完全に同じロジックの重複実装 (DRY されていない)。

## 5. 年表示 + 資産グラフ — 確定 `app.js:2459-2513, 763-`

- `list_display(year)` が `get_year_data` を引き、thumbnail から 12 ヶ月分を frontend 再集計。
- **グラフは自前 `graph()` 関数** (Chart.js 等の外部ライブラリ不使用、§touri-philosophy 整合)。
- グラフデータは **max 値で正規化したパーセント配列** `[["1月", percent], ...]` (`app.js:2459-2477`)。
- 表示切替: 「月末残高の推移」(デフォルト) / タグ選択時は「<tag>タグの推移」(`app.js:2494-2502`)。
- 年ヘッダの `balance_BoIaX` (収支) は全 category の `all` 合計 (`app.js:2583, 2680`)。"BoIaX" は Touri の内部命名 (balance of income and expense ぽい)。

## 6. 汎用/拡張設計の核心 (Touri 重視点) — 実コード検証済

touri-design-philosophy.md の主張を live コードで検証した結果:

- ✅ **Uniform shape + discriminator は本物**だが、**現 live の discriminator は record の `type` フィールドではなく `amount` の符号**。knowledge の「type フィールドで収入/支出を区別」は **やや不正確 → 実際は amount 符号 + category 種別 (proof_text の 1/2) で導出**。新アプリで素直に `type` enum を持たせる方がむしろ明示的で良い (philosophy の「3〜10 種ゾーン」に合致)。
- ✅ **type → CSS クラス派生は実在**: `p-ml__display__month__records__record__icon__${type}` (`app.js:666`)。type 値('inc'/'exp')が直接クラスサフィックスになる。
- ✅ **settings の flat dict 拡張容易性**: categories/tags は id キーの dict、フィールド追加だけで拡張可。
- ✅ **single POST + control discriminator** = 「種別を増やす = control 値を 1 個足す」。これも uniform-shape 思想の API 版。
- ✅ **popup フレームワーク** (`app.js:311-421`): 汎用 `popup(id, drop, submit_fn, drop2, submit_fn2)`。`<id>_cb/_cd/_sb/_sb2` 命名規約で close/decide/submit ボタンを自動配線。2 アクション(保存+削除)を 1 popup で扱う。
- ✅ **application_manager** (`app.js:2971-`): `main(display_name, move)` でビュー切替、`history_display` スタックで「戻る」、`keyboard_control()` で ctrl+s/y/m/n + 矢印キーショートカット (`app.js:3037-3074`)。
- ✅ **FS as DB / バージョンをディレクトリ並列** (v1_117, v1_121...): philosophy 記述どおり確認。

### 新アプリに引き継ぐべき設計筋 (箇条書き)
- record は単一テーブル + `type` discriminator。ただし live の暗黙(符号導出)を **明示 enum 化** する (income/expense/transfer + 将来 subscription 派生)。
- `paid` boolean (live は文字列。新アプリは boolean が素直)。確定/未確定の二値が予測の根幹。
- 予測計算は backend 集約 (frontend 表示専用) を踏襲。
- category → tag の 2 階層分類 + tag color (`$VARIABLE` センチネルは捨て、nullable color に)。
- mutation 後 full re-fetch → TanStack Query invalidate。
- 「概要(discription)で bundle」「all vs paid_only の二系列集計」は UX 資産として継承。
- 削除時の参照整合ガード (STILL_IN_USE 相当)。
- popup/keyboard/history-stack は React 流儀 (modal component + router) に翻訳。生 DOM 機構はそのまま移植しない。

## 7. 未実装プレースホルダ (確定、HTML `app_display.html:243-256`)
全て `onclick="popup_alert(..., '現在利用できません。')"` のダミー:
- **目標収入** / **目標支出** (---)
- **開始日** (1日固定表示、`config.first_day` は存在するが UI 未接続)
- **開始日が祝日の場合を考慮** (しない、`config.case_holiday` 未接続)
- データエクスポート (`html:271`)
→ 新アプリの「締め開始日」「祝日考慮」は **moneylog では未完成**。設計するなら ゼロから。MVP では暦月固定が妥当。

## 8. 旧コピー (common/js/app.js 1820行) との差分
v1_121 が現行 live。旧 1820 行版は機能サブセット (bundle/year graph 未成熟と推測)。**新設計の参照元は v1_121 のみで十分**、旧版は無視可。

---

# Part B — 新アプリ feasibility

## B-1. スタック整合 (確定: npm registry 直確認 2026-06-08)

omatase-demo の構成をそのまま採用可。各依存の最新版 (`npm view` 実行値):

| パッケージ | 最新版 (2026-06-08) | 備考 |
|---|---|---|
| better-auth | **1.6.14** (2026-06-02 publish) | omatase の 1.6.11 から patch 上がりのみ。API 互換 |
| drizzle-orm | 0.45.2 | 据え置き |
| drizzle-kit | 0.31.10 | 据え置き |
| better-sqlite3 | 12.10.0 | 据え置き |
| hono | 4.12.23 | 据え置き |
| @hono/node-server | 2.0.4 | 据え置き |
| zod | 4.4.3 | v4 系。@hono/zod-validator は v4 対応版を |
| vite | 8.0.16 | v8 |
| vitest | 4.1.8 | v4 |
| tailwindcss | 4.3.0 | v4 (CSS-first config) |
| @tanstack/react-query | 5.101.0 | |
| react | 19.2.7 | |
| rrule | 2.8.1 | 定期化で使うなら (B-2 で不要判断) |
| date-fns | 4.4.0 | 月末日計算等の日付処理に推奨 |

★ **結論**: omatase-demo スタックをそのまま採用して問題なし。better-auth は anonymous plugin ではなく **email/password 不要のスタンドアロン認証** が task 前提 (omatase は anonymous だったが moneylog 後継は「個人の家計簿」= 永続アカウントが要る)。→ better-auth の **email+password または社会ログイン** を使う想定。anonymous plugin 知見はそのまま流用せず、標準の emailAndPassword か OAuth を Architect が選択。要・認証方式の最終確認 (不確定)。

詳細な auth.ts/schema/Hono mount/CORS/WAL/app export 規約は `Muraki/knowledge/library/better-auth-hono-drizzle-sqlite.md` と omatase research-summary が **そのまま再利用可** (再掲しない)。

## B-2. 定期化の方式判断 (★推奨あり)

task のスコープ: サブスク/クレカ/給料 = **毎月固定の日に固定額の収入/支出**。クレカは月固定出費扱い (請求サイクル無し)。

### ★ 推奨: RRULE フル実装は不要。「月次ルール (day-of-month + 金額 + category/tag + 符号)」の単純スキーマで足りる。

根拠:
- task のドメインは **FREQ=MONTHLY の単一バリエーションのみ**。週次・隔週・BYDAY 等は要件に無い。
- `rrule-string-onfly-expand-with-overrides.md` が RRULE を推奨するのは「Google/Apple/Outlook 互換・.ics import/export・複雑な繰り返し」が要る場面。**家計の定期支払いは外部カレンダー互換が不要**で、RRULE の表現力はオーバーキル。
- RRULE 文字列保存の利点 (ロスレス import/export) は moneylog 後継では効かない (task: 既存データ import 不要)。
- → **`RecurringRule { id, type, dayOfMonth(1-31), amount(符号付), categoryId, tagId, description, startMonth, endMonth(nullable) }`** で十分。FREQ=MONTHLY 固定なので文字列パーサ依存をゼロにできる (philosophy の「薄い抽象」に合致)。

### 端日 (31日指定で2月など) の扱い
- date-fns の `endOfMonth` / `min(dayOfMonth, daysInMonth)` でクランプ。「31日 → 2月は28/29日、4月は30日」= **その月の最終日にクランプ** が家計簿として自然 (給料日・引き落とし日の実挙動と一致)。
- RRULE の `BYMONTHDAY=-1` 相当を自前 1 行で実装。rrule npm 不要。

### 展開ロジック: on-the-fly か materialize か
`calendar-week-pattern-meeting-expansion.md` の判断基準を適用:
- omatase/atender の Meeting は materialize(MeetingOccurrence)、calendar-rrule は on-the-fly。判断軸は「編集頻度」「件数」「範囲の有界性」。
- 家計の定期ルール: **件数小 (1ユーザー数十ルール)、展開範囲は有界 (現在〜数ヶ月先)、ルール編集は稀**。
- ★ **推奨: materialize (未確定 record を未来へ実体生成)**。理由:
  - moneylog の予測モデルは「record(paid=false)を月に積む」構造。定期ルールから **未確定 record を生成して既存の record テーブルに INSERT** すれば、予測計算ロジックが定期/手動を区別せず同じパスで動く (uniform shape 思想に完全合致)。
  - ユーザーが「今月の給料だけ金額変更」= 生成済み record を直接編集 (= calendar の override を別テーブルで持たずに済む)。
  - 「先何ヶ月分を materialize するか」は固定窓 (例: 今月+12ヶ月) を rolling 生成。月初 cron or ログイン時 lazy 生成。
- on-the-fly 案も可だが、予測計算のたびにルール展開 + 手動 record マージが必要で、moneylog の「record を積む」一元モデルから乖離する。**materialize が筋が良い**。
- 対比: calendar 系が on-the-fly を選ぶのは「無限繰り返し・編集多発・外部同期」だが家計はどれも当てはまらない。

### materialize の設計論点 (Architect へ)
- `RecurringRule` 編集時の既存生成 record の扱い (未来分のみ再生成、過去/編集済みは保護)。calendar の future/single/all 3択に類似するが、家計では「未来の未編集分だけ再生成」で足りる (要 `sourceRuleId` + `isManuallyEdited` フラグ)。
- 二重生成防止: `(ruleId, yearMonth)` ユニーク制約。

## B-3. 未来出費コントロールビュー (数ヶ月先まで)

moneylog の単月 `balance.last` を多月へ拡張する論点:

- **月跨ぎ繰り越し**: `月Nの着地残高 = 月(N-1)の着地残高 + 月Nの収支(確定+未確定)`。moneylog がサーバ内で閉じていた繰り越しを **明示的な累積系列** として設計。`runningBalance[]` を backend で計算して返す。
- **定期ルール由来の未確定をどう各月へ展開して累積残高を出すか**: B-2 の materialize 方針なら、未来各月に未確定 record が既に存在 → 月次集計 (Σ amount) を時系列に累積するだけ。定期/手動の区別不要。
- **API 案**: `GET /forecast?from=YYYY-MM&months=N` → `[{month, incomeConfirmed, incomeExpected, expenseConfirmed, expenseExpected, endingBalanceConfirmed, endingBalanceForecast}]`。moneylog の all/apaid_only 二系列をそのまま多月へ。
- **初期残高 (アンカー)**: 累積の起点。ユーザーが現在の口座残高を 1 回入力 = 起点 record (paid, 確定残高調整) として持つのが moneylog 流。
- ビュー UX は折れ線/棒の月別推移グラフ (moneylog 年グラフの多月版) + 各月の着地予測カード。

## 設計への含意 (Architect 向け要点)

1. ★ **record は単一テーブル + `type` enum (income/expense/transfer)** + `paid` boolean + `sourceRuleId` nullable。moneylog の暗黙符号導出を明示 enum 化。
2. ★ **予測計算は backend 集約**。frontend は計算済み balance を描画 (moneylog 構造踏襲)。
3. ★ **定期化は RRULE 不要、月次ルール (dayOfMonth + 金額 + 符号) で十分**。rrule npm 入れない。端日は最終日クランプ (date-fns)。
4. ★ **定期ルール → 未確定 record を materialize**。予測パスが定期/手動を区別しない uniform model。rolling 窓 (例 12ヶ月) で生成、`(ruleId, yearMonth)` ユニーク。
5. ★ **多月 forecast API** = 月別 all/paid_only 二系列 + 累積残高。初期残高アンカー record が必要。
6. ★ **category → tag 2階層 + tag color (nullable)**。削除時参照整合ガード (STILL_IN_USE 相当)。
7. ★ **mutation 後 TanStack Query invalidate** (moneylog full re-fetch の翻訳)。
8. ★ スタックは omatase-demo そのまま (better-auth 1.6.14 / hono / drizzle / sqlite / vite8 / tailwind4 / TanStack Query)。**認証方式のみ要確認** (anonymous でなく永続アカウント= emailAndPassword or OAuth)。
9. ★ 「概要(description)で bundle」「年/多月推移の自前グラフ or 軽量lib」は UX 資産として継承。
10. ★ 締め開始日/祝日考慮は moneylog 未完成。MVP は暦月固定。将来拡張なら config に。

## 不確定事項 (推測で埋めない)

- **backend 予測アルゴリズムの厳密式**: ローカルにソース無し。frontend 消費形状からの逆算。月跨ぎ繰り越しがサーバ内でどう閉じているかは未確認。→ 新アプリは多月累積を明示設計するので影響小。
- **`config.first_day` の実挙動**: settings に存在するが frontend 未使用、HTML はプレースホルダ。現 live が暦月で動いているか締め日で動いているか未確認。
- **新アプリの認証方式**: task は「better-auth スタンドアロン」までしか確定していない。email/password か OAuth か未確定 (Architect 召集前に Leader が Touri 確認推奨)。
- **save_record の amount 上限/負数許容範囲・date のタイムゾーン扱い**: backend 仕様未確認。新規設計で UTC/JST を Architect が明示すること。
