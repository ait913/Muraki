---
title: UI/UX 設計の汎用観点集 (Web + SwiftUI 共通、出典タグ付き)
category: pattern
project: global
tags: [ui, ux, hig, typography, spacing, color, dark-mode, navigation, ia, cognitive-load, accessibility, design-perspectives]
created: 2026-07-05
sources:
  - Muraki/projects/_pre/research-apple-hig-20260705.md (HIG 一次ソース抽出。個別 URL は同 doc 参照)
  - Muraki/projects/_pre/research-ux-ia-cognitive-load-20260705.md (NN/g / lawsofux / Wikipedia 抽出)
  - https://developer.apple.com/design/human-interface-guidelines/
  - https://www.nngroup.com/articles/
---

## Context

Muraki の Architect が設計doc の UI/UX 節を書くとき・Leader/Reviewer が UI を評価するときに**通す観点の集合**。Touri の要望「Apple ガイドラインベースの要素感覚 + フォント/サイズ/余白の整備」「最短到達・最小情報量・認知負荷低減のページ/タブ設計」を、Web と SwiftUI iOS の両方で使える形に固定したもの。

**これはルールブックではなく観点集**。Muraki はエキスパート制であり、判断を縛る網羅ルールは置かない。使い方は 2 つだけ:

1. 設計時にこの観点を**通す** (該当する節を読み、考慮した痕跡を設計doc に残す)
2. 数値は**初期値**として使う。逸脱してよいが、**逸脱するなら設計doc に理由を 1 行書く**

**責務分担 (重複禁止)**: 本ファイルは**汎用層**のみ。プロジェクト固有の視覚言語 (色トークン実値・radius・質感・アイコンセット) は各 PJ の `DESIGN.md` / `.knowledge/` 側 (例: kinketsu-taisaku の DESIGN.md、[`moneylog-design-language.md`](moneylog-design-language.md))。個別 UI 部品の実装 BP は既存パターン ([`form-modal-readability-bp`](form-modal-readability-bp.md) / [`mobile-first-bottom-tab`](mobile-first-bottom-tab.md) / [`home-aggregated-context-switcher`](home-aggregated-context-switcher.md) / [`mobile-density-tighten-token-pass`](mobile-density-tighten-token-pass.md)) に既にある。本ファイルから参照するだけで、内容を再掲しない。

**出典タグ凡例** (全数値に付与。タグの信頼度 = 逸脱時の説明責任の重さ):

| タグ | 意味 |
|---|---|
| [HIG] | Apple HIG 現行版 (2025-06 以降の Liquid Glass 世代) の明文 |
| [NN/g] | Nielsen Norman Group の研究記事 |
| [WCAG] | WCAG 2.x 達成基準 |
| [慣習] | 業界慣習。一次ガイドライン出典なし。逸脱の自由度が最も高いが、チーム内の一貫性のために初期値を決めてある |

注意: 現行 HIG は Liquid Glass 世代。旧 HIG の「hierarchy / flat / content-driven の 3 分類」は現行に存在しないので設計doc に書かない。tab bar / toolbar は「content の上に浮く層」であり、コンテンツは画面端・コントロール下まで伸ばす [HIG]。

## What

### §1 タイポグラフィ

**観点: サイズは階層の符号。フリーハンドで決めず、段階スケールから割り当てる。**

- iOS 本文の初期値 **17pt**、最小 **11pt** [HIG]。macOS は 13pt / 最小 10pt [HIG]。Web 本文は 14-16px [慣習] (密度重視アプリは 14、読み物は 16)
- iOS は **built-in text style を使う** (Dynamic Type + アクセシビリティサイズが自動で効く) [HIG]。カスタムサイズを切るのは text style で表せない時だけ
- Dynamic Type (Large 既定) の主要段 [HIG]:

  | Style | Size/Leading (pt) | 用途の目安 |
  |---|---|---|
  | Large Title | 34/41 | 画面タイトル (スクロールで standard へ) |
  | Title 2 | 22/28 | セクション大見出し・大数値 |
  | Headline | 17/22 semibold | 強調本文・行タイトル |
  | Body | 17/22 | 本文 |
  | Subhead | 15/20 | 副次情報 |
  | Footnote | 13/18 | メタ情報 |
  | Caption 1/2 | 12/16・11/13 | キャプション最小段 |

- Web への転用: 1pt ≒ 1px 読み替え [慣習、HIG 明文ではない]。Dynamic Type の代替は **rem ベース + ブラウザ文字サイズ尊重** (px 固定 root を避ける)
- **Light / Ultralight / Thin weight を使わない** (特に小サイズ)。Regular / Medium / Semibold / Bold の 4 つで組む [HIG]
- 3 行以上のテキストに tight leading を使わない [HIG]。本文 leading は 1.4-1.6 [慣習]
- テキストは **200% まで拡大可能**に (truncation で壊れない layout) [HIG/WCAG 1.4.4]
- サイズの**段数は 1 画面あたり 3 段まで** (small/medium/large を超えると階層関係が読めなくなる) [NN/g §6 と同根]
- 日本語の行間・字詰めの個別数値は **HIG に存在しない** (不確定)。日本語 UI は Noto Sans JP / Hiragino 等 + leading 広め (1.5-1.7) が実務初期値 [慣習]

### §2 Spacing・レイアウト

**観点: 余白はグルーピングの主手段。罫線や枠でなく、余白と面で構造を作る。**

- タップターゲット: **44x44pt 以上** [HIG]、iOS の絶対最小 28x28pt [HIG]。Web も 44x44px を初期値に (WCAG 2.5.8 の最小 24px より厳しい Apple 基準を採る) [HIG]/[WCAG]
- 要素周囲の空間: **bezel あり要素の周囲 約12pt、bezel なし (ボーダーレス) 要素の可視端周囲 約24pt** [HIG] — HIG が明文化する唯一の余白数値。これ未満に詰めるなら理由を書く
- **8px (4px 刻み) グリッドは HIG に存在しない** [慣習]。ただし Muraki の Web 実装では「spacing/radius を 4/8px グリッドの token に乗せ、ハードコード px を書かない」を初期値とする (チグハグ防止の実績: kinketsu-taisaku DESIGN.md)。**「HIG 準拠の 8pt グリッド」とは書かない**
- spacing token は**用途 (semantic) で段を固定する**: コンポーネント内 padding / 要素間 gap / セクション間 margin / 隔絶余白、の 4 用途にそれぞれ 1-2 段を割り当てる [慣習]。値そのものより「同じ用途に同じ段」が一貫性を作る
- iOS: **full-width ボタンを避け、システムマージン内に inset** [HIG]。safe area (Dynamic Island / home indicator) を尊重 [HIG]。Web は `env(safe-area-inset-*)` ([`mobile-first-bottom-tab`](mobile-first-bottom-tab.md) 参照)
- 片手持ち前提: **主要コントロールは画面中央〜下部** (親指到達域) [HIG]。back swipe・list row swipe を塞がない [HIG]
- 最優先要素 (hero 数値等) は**大きめの余白で孤立させる** — 余白そのものが強調 [NN/g]

### §3 色・ダークモード・コントラスト

**観点: 色は意味 (状態・符号・アクション) にだけ使う。優先度・階層は size/weight/余白で表す。**

- **semantic color を使い、色値をハードコードしない** [HIG]。Web では CSS 変数 (トークン) 経由に統一 [慣習]。semantic の意味を転用しない (separator 色を文字に使う等) [HIG]
- コントラスト最小値 [WCAG AA / HIG 同値]:

  | 対象 | 最小比 |
  |---|---|
  | 〜17pt (Web ≒ 〜23px) テキスト | **4.5:1** |
  | 18pt 以上 or Bold | 3:1 |
  | 非テキスト UI (focus ring・border・アイコン) | 3:1 [WCAG 1.4.11] |

  カスタム前景/背景色は **7:1 を目標** (特に小テキスト) [HIG]
- **アプリ内独自の appearance (light/dark) 切替 UI を作らない** — OS 設定に従う [HIG]。Web は `prefers-color-scheme` 一本 [慣習]
- dark palette は light の**単純反転ではない** [HIG]。iOS は base / elevated の 2 セット (sheet・popover で自動昇格) があり、カスタム背景色はこの奥行きを壊す [HIG]。白背景画像は dark 文脈で「光る」ので少し暗くする [HIG]
- accent color は**強調に値する要素 (primary action・状態) だけ** [HIG]。prominent ボタンは文字でなく**背景**に accent を塗る [HIG]。複数コントロールに同時に色を付けない [HIG]
- **色だけで情報を伝えない** — shape / icon / text を併用 [HIG/WCAG 1.4.1]

### §4 コンポーネント観点

**観点: 各コンポーネントの「役割の純度」を守る。タブに action を置かない、modal に階層を作らない、が典型。**

- **ボタン**: prominent (塗り) スタイルは **1 view に 1-2 個まで** [HIG]。優先度差はサイズでなくスタイルで表す [HIG]。破壊的アクションに primary role を与えない (destructive = red 系 + 非 primary) [HIG]。非即時アクションはボタン内で進行表示 + ラベル変化 ("保存"→"保存中…") [HIG]
- **sheet / modal**: modal は「明確な利益がある時だけ」。タスクは短く単純に [HIG]。**modal 内に階層を作らない** (app within app 禁止) [HIG]。**sheet は同時 1 枚** — sheet から sheet を出すなら先に閉じる [HIG] (SwiftUI では sibling sheet の同時宣言事故に注意: [`gotcha/swiftui-multiple-sibling-sheets-only-one-fires`](../gotcha/swiftui-multiple-sibling-sheets-only-one-fires.md))。Cancel = leading / Done = trailing [HIG]。swipe-dismiss 可 + 未保存変更あれば確認 [HIG]。フォーム視認性は [`form-modal-readability-bp`](form-modal-readability-bp.md)
- **toolbar (navigation bar)**: タイトル 15 字以内・アプリ名をタイトルにしない [HIG]。アクショングループは最大 3 [HIG]。prominent な primary action は 1 つだけ trailing 側 [HIG]。標準 Back/Close 部品を使う [HIG]。large title のスクロール遷移で現在地を伝える [HIG]
- **tab bar**: **navigation 専用。アクションを置かない** [HIG]。タブ数の固定上限は現行 HIG に**無い** — 現行表現は「少ないほど良い + overflow (More) を避ける」[HIG]。3-5 という数字は旧 HIG / MD3 由来 [慣習]。タブを隠さない・disable しない (空なら empty state で理由を示す) [HIG]。ラベルは 1 単語 + アイコン filled variant [HIG]。Web 実装は [`mobile-first-bottom-tab`](mobile-first-bottom-tab.md)
- **sidebar**: まず tab bar を検討 (コンテンツに空間を譲れる) [HIG]。sidebar 内階層は 2 レベルまで、超えるなら split view [HIG]
- **アイコン**: 単一セットに統一し、weight を隣接テキストと一致させる (SF Symbols は 9 weight が SF と 1:1) [HIG]。outline = テキスト併記の場所 / fill = tab bar・選択状態 [HIG]。Web は lucide 等 stroke 系 1 セット + サイズ 2-3 段固定 [慣習]

### §5 IA・ナビゲーション (最短到達)

**観点: 最適化するのはクリック数ではなく interaction cost (読む・理解する・覚える・移動する努力の総和)。**

- **神話を輸入しない** (根拠として書いたら差し戻し対象):
  - 「3 クリックルール」は**偽** — 3 クリック超でも離脱率・満足度は悪化しない (Porter 2003 が反証) [NN/g]。クリック数削減のために scent の弱い巨大メニューを作るのは本末転倒
  - 「メニューは 7±2 項目まで」は Miller の**誤用** — メニューは recognition であり短期記憶を使わない。構造化されていれば 7 超で問題ない [NN/g]。7±2 の正しい適用先は「画面間で記憶を持ち越させない」こと
  - Hick's Law (選択肢数→決定時間の対数則) は**未整列リストには不成立** (探索は線形時間) [NN/g/Wikipedia]。タブ・ボタン数を絞る根拠にはなるが、リストでは**ラベルの scent とグルーピングの方が支配的**
- **information scent**: リンク/タブ/ボタンのラベルは具体的に。「詳細」「もっと見る」のような曖昧語を避け、押した先で何が出るかをラベルが約束し、必ず果たす [NN/g]
- **broad > deep**: 深い階層の害はクリック数でなく**方向感覚の喪失** [NN/g]。カテゴリが明確に分かれるならフラットに 8-16 個並べる方が良い。ただしフラット 30+ 項目は決定麻痺 [NN/g]
- **wayfinding**: 現在地を常に明示 (large title / 選択タブの強調 / パンくず) [HIG]/[NN/g]
- **Jakob's Law**: ユーザーは他のアプリで大半の時間を過ごす。慣習的なラベル・配置に乗るほど学習コストが消え、タスクに集中できる [NN/g]。革新するなら段階導入
- **ナビ構造の選択基準** (統合推論、単一出典なし):

  | アプリの性質 | 初期候補 |
  |---|---|
  | 毎回同じ 1 タスク (記録・確認) | **1 画面 + progressive disclosure** (moneylog 型。タブで割らない) |
  | 対等なコンテキストを数個往復 | bottom tab (少数) / context chip ([`home-aggregated-context-switcher`](home-aggregated-context-switcher.md)) |
  | 低頻度機能が多数 | タブに載せず二次階層 (設定画面) へ |

### §6 情報密度と認知負荷

**観点: 削るのは extraneous load (理解に寄与しない処理) だけ。intrinsic load (情報そのもの) を削って要望を縮小しない。**

- extraneous load 削減の 3 手法 [NN/g]: (1) 視覚クラッタ除去 (冗長リンク・無意味な装飾) (2) 既存メンタルモデル活用 (慣習ラベル・レイアウト) (3) **認知タスクのオフロード** — 計算・記憶・判断をシステム側へ (事前入力・賢いデフォルト・自動集計)
- **progressive disclosure**: 初期表示は最重要オプションだけ、残りは要求時に [NN/g]。成功条件は (1) 初期/二次の切り分けを**タスク頻度**で決める (2) 進行手段のラベルに強い scent。**開示は 2 段まで** — 3 段以上は方向感覚を失う [NN/g]。何を初期に置くかを analytics 単独で決めない (偶然クリックと区別できない) [NN/g]
- **視覚階層**: 目が重要度順に要素を消費するように、色コントラスト / スケール (3 段まで) / 余白グルーピングで組む [NN/g]。視覚的重要度と実際の重要度が一致していることをレビューで確認
- **デフォルト値**: ユーザーはデフォルトに強く従う (位置が品質より行動を支配する実証あり) [NN/g]。デフォルト = 最頻値。デフォルトは期待される回答形式の説明としても機能しエラーを減らす [NN/g]
- **empty state を設計する** (放置しない): (1) システム状態の区別 (loading / no results / error) (2) ここに何が入るかの学習手がかり (3) 主要タスクへの直接経路 (Create ボタン) [NN/g]。タブが空でも隠さず理由を示す [HIG]
- **長ページ回避は神話**: 関連性があり整理されスキャン可能ならユーザーはスクロールする。スクロールは accordion をどれ開くか決めるより安い [NN/g]。accordion はモバイルの長大ページでは有効、デスクトップで大半の内容が必要なユーザーには全文表示 [NN/g]
- 密度を上げたい時は個別調整でなく token 一括パス ([`mobile-density-tighten-token-pass`](mobile-density-tighten-token-pass.md))

### §7 設計doc の UI/UX 節を書くときのチェック観点 (Architect 向け)

設計doc に以下を**明記**する (曖昧表現で逃げない)。全部書けというルールではなく、該当するのに書いていない項目があれば理由を持つこと:

1. **視覚階層の割当表**: この画面の最優先要素はどれか。L0 (隔絶・1 要素) / L1 / L2 / L3 (meta) に要素を割り、size・weight・余白の段を対応させる (§1, §6)
2. **タスク頻度 → 動線表**: 最頻タスクのタップ数、各機能の配置 (常時可視 / 1 タップ / 二次階層)。頻度の根拠 (タスク分析) を 1 行 (§5, §6)
3. **token 参照先**: PJ に DESIGN.md があればそれを正典として参照。なければ本ファイルの初期値で仮 token を切り、数値をハードコードで散らさない (§2)
4. **状態の網羅**: empty / loading / error / 権限なし の各状態で何が出るか (§6)。Reviewer はここからテストを書く
5. **アクセシビリティ最低線**: tap target 44px、コントラスト 4.5:1、focus-visible ring (非テキスト 3:1)、200% 拡大耐性 (§2, §3)
6. **dark 対応方式**: OS 追従 (`prefers-color-scheme` / システム設定)。手動トグルを作るなら理由 (§3)
7. **ナビ構造の選択理由**: §5 の表のどれに該当し、なぜか。タブを増やす・階層を深くする変更では「現在地明示」と「2 段制限」を確認
8. **数値の逸脱理由**: 本ファイルの初期値から外れる箇所は、外れる値と理由を 1 行

## Why

- HIG / NN/g / WCAG は一次ソースの主張が互いに矛盾せず、Web と SwiftUI の両方に翻訳可能な共通核を持つ (44pt、コントラスト比、progressive disclosure、少ないタブ)。この核だけを汎用層に固定し、質感 (色・radius・アニメ) は PJ 層に残すと、プロジェクト間で「観点は共通・見た目は自由」が成立する
- 出典タグを義務化したのは、過去に「8pt グリッド」「タブ 3-5」「3 分類ナビ」等の**慣習・旧世代記述を HIG 出典と誤認して輸入する**事故経路が確認されたため (2026-07-05 リサーチで HIG 原文に不在と確定)。タグがあれば逸脱判断の重さを個々に見積もれる
- 神話の明示的否定を残すのは、3 クリックルール・7±2 が Web 記事経由で再輸入されやすく、これを根拠にした設計 (scent を犠牲にした階層圧縮・機能削減) が interaction cost をむしろ増やすため [NN/g]
- Touri の中核思想「開いて即・最短・直感」(moneylog) は §5 の interaction cost 最小化・§6 の progressive disclosure と同じ方向であり、本観点集は思想の置き換えでなく出典付きの裏付けとして機能する

## How to apply

- **Architect**: 設計doc の UI/UX 節を書く前に §7 のチェック観点を通す。数値は初期値として使い、逸脱には理由を 1 行。神話 (§5) を根拠に書かない
- **Leader / Reviewer**: UI 評価時に「視覚階層とタスク頻度の割当が doc に明記されているか」「[慣習] 数値を HIG 出典と書いていないか」を見る
- 本ファイルは汎用層。PJ 固有の視覚言語を足したくなったら、ここに書かず PJ の DESIGN.md / `.knowledge/` に置く
- HIG は年次で書き換わる (Liquid Glass 世代で navigation ページ構成が変わった実績)。HIG 出典の記述を追加・更新するときは JSON エンドポイント (`developer.apple.com/tutorials/data/design/human-interface-guidelines/<slug>.json`) で現行原文を確認してから書く
