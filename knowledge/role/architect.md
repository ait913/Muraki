# Architect の職業的習慣ノート

召集されたら最初に読む。**過去の自分 (歴代 Architect) が実際に踏んだ穴**であり、予防的な網羅ルールではない。新しく踏んだら自分で追記・置換する (INDEX 対象外、再生成不要)。

- **横断的変更 (母数・型・命名規約の変更) では、影響を受ける既存テストを grep で機械的に洗い出してから移行リストを書く。** 目視列挙で rule-scope.test.ts が漏れ、developer 初回実装が 14 件全滅した実績 (sessions/2026-06-11)
- **導出値の手計算を doc に書かない。生成規則だけを書く。** 規則と手計算が矛盾したら規則が規範になり doc は errata になる — 最初から手計算を書かなければ起きない (gotcha/design-doc-derived-counts-vs-generative-rule.md)
- **描画テスト対象のコンポーネントは公開 prop 契約 (フィールド名・形・コールバック引数) を明記する。** 欠落すると Reviewer が prop 形を推測して偽陰性 YELLOW (gotcha/design-must-specify-component-prop-contract-for-render-tests.md)
- **型付き言語 (Swift 等) は挙動仕様だけでなく DTO の Optional 性・enum・VM の public API・init まで書く** (gotcha/design-doc-must-specify-swift-type-signatures.md)
- **データ源が要望に足りなく見えても、要望を縮小した設計を出さない。** 要望文言の含意 (件数・動作) から必要データ量を逆算し、既存ユーティリティで埋められないか先に当たる。縮小初稿を Leader に差し戻された実績 (sessions/2026-06-02)
- **並列 2 設計のときはスコープ境界 (どのファイル・ディレクトリがどちら専属か) を両 doc の冒頭に明記する。** マージがコンフリクトゼロになった成功例 (sessions/2026-06-11)
- **「〜をベースに/コピーして」型の要望では、fidelity (元実装への忠実) と curation (設計原則による選別) のどちらが契約かを設計前に確定する。** dandan-app で原則準拠の選別設計 (画面絞り込み・ツール統合・policy 不採用推奨) が Touri 裁定「不採用判断いらんからコピーして」で全面書き直しになった (2026-07-07)。コピー契約なら doc の本丸は「忠実度テーブル (全構成要素に コピー / 機械変換+必然理由 / additive を割り、捨てる行ゼロ)」であり、改善提案は「やらない変換」として不採用案に隔離する
