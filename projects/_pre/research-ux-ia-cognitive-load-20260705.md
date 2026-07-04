# Research: UX/IA — 最短到達ナビゲーションと認知負荷低減 (2026-07-05)

依頼: 「ページやタブデザインについても、ユーザーが最短で目的の機能にたどり着けるように、尚且つ必要最小限の情報量で認知負荷を下げより集中できるようにしたい」の設計観点集の素材。
調査経路: WebSearch + WebFetch (gemini CLI は IneligibleTierError で不使用)。NN/g 記事・Apple HIG (JSON エンドポイント直読み)・lawsofux (原典引用付き)・Wikipedia (Hick's law の限界、原論文引用付き)。

---

## 1. 認知負荷理論の UI 適用

### 1.1 認知負荷の定義と分類 — NN/g "Minimize Cognitive Load"
https://www.nngroup.com/articles/minimize-cognitive-load/

- 認知負荷 = 「システムを操作するのに必要な精神的リソースの総量」
- **intrinsic load**: 情報の吸収・ゴールの追跡に必要な負荷。**削れない・削るべきでない**
- **extraneous load**: 「精神リソースを消費するが内容理解に寄与しない処理」(装飾タイポグラフィ等)。**削減対象はこちらのみ**
- 削減の 3 手法:
  1. **視覚的クラッタの除去**: 冗長リンク・無関係画像・意味のない装飾を消す
  2. **既存メンタルモデルの活用**: 他サイトで馴染みのあるラベル・レイアウトを使う (学習コスト削減)
  3. **認知タスクのオフロード**: 計算・記憶・判断をシステム側へ移す — テキストの画像化、事前入力、賢いデフォルト値
- chunking と応答速度最適化も同じ目標に資する

### 1.2 Hick's Law — lawsofux + Wikipedia (原論文: Hick 1952 / Hyman 1953)
https://lawsofux.com/hicks-law/ , https://en.wikipedia.org/wiki/Hick%27s_law

- 「決定時間は選択肢の数と複雑さに応じて増加する」。等確率選択肢では T = b·log₂(n+1) の**対数**関係
- 設計適用 (lawsofux): 応答速度が重要な場面では選択肢を減らす / 複雑なフローは段階分割 / 推奨選択肢の強調 / 新規ユーザーへの段階的機能導入 / **ただし意味のある区別まで消す過剰単純化はしない**
- **限界 (Wikipedia、盲信への警告)**:
  - **未整列リストの探索は線形時間** (各項目を読む必要があるため対数則が成立しない)
  - 熟達した反応 (慣れた操作) は選択肢が増えても反応時間がほぼ増えない
  - アルファベット順メニューで対数性能が出るのは「目的の名前を知っている」場合のみ
- 含意: Hick's Law は「タブ数・ボタン数を絞る根拠」には使えるが、「メニュー項目を読む時間」は項目数に線形なので、**ラベルの scent とグルーピングの方が支配的**

### 1.3 Miller の 7±2 の現代的評価 — NN/g "Chunking"
https://www.nngroup.com/articles/chunking/ , https://www.nngroup.com/videos/magical-number-7-ux/

- Miller (1956): 短期記憶は「約 7 チャンク」。ただし**チャンクのサイズは可変** — 7 文字でも 7 単語 (28文字) でも同じく保持できる
- **「メニューは 7 項目まで」への誤用を NN/g は明確に否定**: メニューは**recall (想起) でなく recognition (再認)** — 選択肢は画面に表示されており短期記憶に保持する必要がない。意味のある構造化がされていれば 7 超でも問題ない
- 正しい適用先: **画面間で記憶を持ち越させない** (recall を発生させない)、コンテンツを意味単位に chunking する
- chunking 手法: 短い段落 + 余白 / 見出し階層 / 箇条書き / 慣習フォーマット (電話番号・日付) / 近接・整列・背景色でのグループ化

### 1.4 Jakob's Law — lawsofux (原典: Jakob Nielsen / NN/g)
https://lawsofux.com/jakobs-law/

- 「ユーザーは他のサイトで大半の時間を過ごす。だからあなたのサイトも他と同じように動くことを望む」
- 既存メンタルモデルに乗ることで、ユーザーは UI の学習でなく**タスク遂行に集中**できる
- 停滞の言い訳にはしない: 革新するなら段階導入 + 旧版への一時復帰手段 (YouTube 2017 redesign の例)

---

## 2. 最短到達 IA

### 2.1 3クリックルールは神話 — NN/g "The 3-Click Rule for Navigation Is False"
https://www.nngroup.com/articles/3-click-rule/

- 「データに裏付けのない恣意的な経験則」。起源は Zeldman 2001 (無根拠)。Joshua Porter (2003) の研究が反証: **3 クリック超でも離脱率・満足度は悪化しない**
- 問題点: タスク複雑度は可変 / クリックは等価でない (ページロード付きと accordion 展開は別物) / クリック数は体験の全体を語らない
- 代わりに最適化すべき: **information scent の強いラベル / wayfinding (現在地明示) / ページロード時間**

### 2.2 Interaction cost が正しい指標 — NN/g "Interaction Cost"
https://www.nngroup.com/articles/interaction-cost-definition/

- interaction cost = 「ゴール到達までにユーザーが払う**精神的+身体的努力の総和**」。クリック・タイピング・スクロールだけでなく、**読む・理解する・ページ間で記憶する・注意を切り替える**も含む
- 「usability の直接的な尺度」— あらゆる usability ヒューリスティックは interaction cost 最小化に帰着する
- ユーザーは期待効用 (利益 − コスト) で行動を選ぶ。**リストをスキャンするより数文字タイプする方が認知的に安ければそちらを選ぶ**。低モチベーションユーザーはコスト過多で即離脱

### 2.3 Information scent — NN/g "Information Scent" (Pirolli & Card の information foraging theory)
https://www.nngroup.com/articles/information-scent/

- ユーザーは「このリンク先に答えがある見込み」と「かかる時間」の不完全な推定 (= scent) でリンクを選ぶ
- scent を構成する 4 要素: リンクラベル / 周辺コンテンツ (要約・画像) / ページ文脈 / 事前知識 (ブランド・慣習)
- 設計指針: **具体的で jargon のないラベル** (「Learn More」のような曖昧語を避ける) / ラベルの約束をリンク先で必ず果たす (clickbait は信頼を毀損)

### 2.4 Broad vs deep 階層 — NN/g "Flat vs. Deep Website Hierarchies"
https://www.nngroup.com/articles/flat-vs-deep-hierarchy/

- **深い階層の害はクリック数そのものでなく方向感覚の喪失**: 「ユーザーは迷い、気が散り、面倒になって諦める」。中間層が増えるほどコンテンツの発見性が下がる
- フラットが有効: カテゴリが明確に区別でき、8-16 個程度の具体的選択肢に自然に分かれるとき
- 深い階層が有効: 1 レベルに収まらない量 / 中間カテゴリページが文脈を与えるとき
- ただしフラットでも 30+ 項目は決定麻痺を起こす。検証は tree testing / card sorting / 検索ログで

### 2.5 頻度ベースの機能配置 — NN/g "Progressive Disclosure" 内
https://www.nngroup.com/articles/progressive-disclosure/

- 初期表示に何を置くかは**タスク分析 + フィールド調査 + (既存システムなら) 利用頻度データ**で決める
- **analytics 単独は誤誘導**: クリックされていても「使いたくて使った」のか「偶然踏んだ」のか区別できない。観察テストで補完する

---

## 3. Progressive disclosure

### 3.1 本体 — NN/g "Progressive Disclosure"
https://www.nngroup.com/articles/progressive-disclosure/

- 定義: 「最初は最重要オプションだけを見せ、要求に応じて特化オプション群を出す」。高度な・低頻度の機能を二次画面に先送りする
- 効果: **learnability / efficiency / エラー削減**の 3 つを同時に改善。初心者は本質機能に集中でき、上級者は低頻度オプションのスキャンを免れる。機能に優先順位がつくとシステム理解自体が向上する (研究による)
- **progressive vs staged**: progressive = 初期表示 + 階層的に二次オプションへ (時々アクセスする機能向け)。staged = wizard 的な線形ステップ (手順が独立しているタスク向け)
- 成功条件 2 つ: (1) 初期/二次の**切り分けの正確さ** — 高頻度機能を過不足なく初期に置く (2) **進行手段の明白さ** — 強い scent のラベルで「開いたら何が出るか」の期待を設定
- **開示レベルは 2 段まで**。3 段以上は方向感覚を失わせる

### 3.2 Accordion の使い所と乱用 — NN/g "Accordions on Desktop"
https://www.nngroup.com/articles/accordions-complex-content/

- モバイルでは有効: 長大ページのスクロール前離脱を防ぎ、概観を与える
- デスクトップでの害: セクションごとのクリック強制 — 「どんなに小さくても全ての決定が認知負荷を足す」/ 折り畳まれた情報は見落とされる / 印刷・アクセシビリティのコスト
- **ページ内容の大半が必要なユーザーには全文表示が正解**: 「関連性があり整理されスキャン可能なら、ユーザーはスクロールする」。長ページ回避は時代遅れの神話。**スクロールは accordion をどれを開くか決めるより安い**

---

## 4. タブ/ナビゲーション実践

### 4.1 Apple HIG "Tab bars" (JSON エンドポイントから本文取得)
https://developer.apple.com/design/human-interface-guidelines/tab-bars

- 目的: アプリの情報/機能の種類を理解させ、**セクション間を即座に切替**。各セクション内のナビゲーション状態は保持される
- **タブはナビゲーション専用。アクションには使わない** (アクションは toolbar)
- タブ数は「複雑さと高頻度セクションへのアクセスのバランス」で決める。**少ないほど良い**。あふれて "More" タブ化するのを避ける (隠れたコンテンツは到達も気づきも困難)
- **タブの無効化・非表示は絶対にしない** — UI が不安定・予測不能に見える。空なら「なぜ空か」を説明する (empty state)
- **ラベル必須、可能なら 1 単語**。SF Symbols 推奨、選択状態は filled で明示
- バッジは重要情報のみに限定 (乱用すると効果が薄まる)
- iPadOS ではタブバー ↔ サイドバー変換可。階層が複雑なら sidebar を検討

### 4.2 Apple HIG "Designing for iOS"
https://developer.apple.com/design/human-interface-guidelines/designing-for-ios

- 中核原則: 「**画面上のコントロール数を制限し、二次的な詳細・アクションは最小限の操作で発見可能にする**ことで、主要タスクとコンテンツへの集中を助ける」(= progressive disclosure の HIG 版)
- エルゴノミクス: 主要コントロールは**画面中央〜下部** (親指到達域) へ。戻る操作・リスト行アクションは swipe を許す

### 4.3 モバイルナビパターン比較 — NN/g "Basic Patterns for Mobile Navigation"
https://www.nngroup.com/articles/mobile-navigation-patterns/

- **タブバー/ナビバー**: 主要ナビ 5 個以下向け。常時見える = 効率的。ラベルをアイコンに併記
- **ハンバーガー**: 多数の選択肢を省スペースで収容できるが「out of sight is out of mind」— 発見性が低く開かれない。閲覧中心 (タスク非中心) サイト向け
- **ナビゲーションハブ (hub-and-spoke)**: 全選択肢を 1 ページに可視化。**1 セッション 1 タスク型アプリに最適** (例: フライトチェックイン)。切替のたびにホームへ戻るコストが欠点
- 原則: コンテンツ優先、ただしナビは発見可能に保つ

### 4.4 1画面主義が有効な条件 (統合)

- hub-and-spoke の「1 セッション 1 タスク」条件 (4.3) + タブバーの「セクション間高速切替」(4.1) の使い分け:
  - 毎回同じ 1 タスク → 1 画面 + progressive disclosure (moneylog 型)
  - 数個の対等なコンテキストを行き来 → bottom tab (5 以下)
  - 低頻度機能が多数 → タブに載せず二次階層 (設定画面等) へ

---

## 5. 情報密度と focus

### 5.1 視覚階層 — NN/g "Visual Hierarchy"
https://www.nngroup.com/articles/visual-hierarchy-ux-definition/

- 定義: 「意図した重要度の順に目が要素を消費するよう設計要素を組織すること」
- 手段: **色/コントラスト** (彩度の高い色が優先項目、muted は後退。bold/italic も階層信号) / **スケール** (サイズ変化は **3 段階まで** — small/medium/large を超えると階層関係が崩れる) / **余白とグルーピング** (周囲の余白 = 強調、近接 = 関連)
- 効果: 「どこを見るべきか」の迷いを消す = 認知負荷の直接削減。視覚的重要度がコンテンツの実際の重要度と一致しているとタスク完了と信頼が上がる

### 5.2 削る判断基準 (統合)

- extraneous load の定義がそのまま基準: 「内容理解に寄与しない処理を発生させる要素」を消す (1.1)
- 初期表示に残すものは**タスク分析 + 利用頻度**で決める。analytics 単独は不可 (2.5)
- 消すのではなく**移す**選択肢: 二次階層へ (progressive disclosure、ただし 2 段まで)

### 5.3 デフォルト値による決定回避 — NN/g "The Power of Defaults"
https://www.nngroup.com/articles/the-power-of-defaults/

- ユーザーはデフォルトに強く従う: Joachims et al. (Cornell, 2005) — 検索結果の上位 2 件を入れ替えても元 1 位位置が 34% クリック (2 位位置は 12%)。品質でなく位置 (デフォルト) が行動を支配
- デフォルトは「最頻値」を選ぶ (例: イベント開催国を国フィールドに事前入力)
- デフォルトは「just-in-time の説明」としても機能 — 期待される回答形式を教え、エラーを減らす

### 5.4 Empty state — NN/g "Designing Empty States in Complex Applications"
https://www.nngroup.com/articles/empty-state-interface-design/

- 空白のまま放置すると: システムが動いているのか確信できない / 機能を学べない / 次に何をすべきか分からず離脱
- 3 ガイドライン: (1) **システム状態の伝達** (loading / no results / error の区別) (2) **学習の手がかり** (ここに何が入りうるか・どう埋めるか) (3) **主要タスクへの直接経路** (Create ボタン等)

---

## 不確定事項

- lawsofux.com は二次ソース (原論文引用付きキュレーション)。Hick 1952 / Hyman 1953 の限界条件は Wikipedia 経由で補完したが原論文には直接当たっていない
- NN/g "mobile-navigation-patterns" の「5 個以下」とタブ数指針は記事要約ベース。Apple HIG 現行版はタブ数の固定上限を明示せず「少ないほど良い + overflow 回避」に変わっている (旧 HIG の「3-5」は現行ページに存在しない可能性が高い) — **タブ数を固定値で規定するなら HIG 現行版の「overflow するな」を根拠にする方が安全**
- 「1画面主義が有効な条件」(4.4) は複数ソースからの統合推論であり、単一出典はない
