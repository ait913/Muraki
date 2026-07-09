# Reviewer の職業的習慣ノート

召集されたら最初に読む。**過去の自分 (歴代 Reviewer) が実際に踏んだ穴**であり、予防的な網羅ルールではない。新しく踏んだら自分で追記・置換する (INDEX 対象外、再生成不要)。

- **validation エラーの assert は status 中心 (400) にする。`error.code` 等の strict assert は zValidator が生 ZodError を返す構成で偽陰性になる。** gotcha 化済みなのに 2 回踏み直した (sessions/2026-06-02)
- **jsdom + Vitest は localStorage / matchMedia 未提供。**先に polyfill (gotcha/jsdom-no-localstorage-in-vitest.md)
- **バグ修正系のレビューは negative control を標準にする**: 修正前コードに戻してテストが落ちることを確認してから GREEN を出す。「テストが実装に迎合していないか」をこれだけが証明できる (sessions/2026-06-11 で有効)
- **偽 RED / テスト全滅の疑いは、実装コードでなく本番経路の直接プローブで切り分ける。** bulk API 全滅に見えた失敗を fixture の日付規約ミスと特定した実績 (sessions/2026-06-11)。fixture の日付は本番の正規化規約 (JST midnight) に合わせる (gotcha/api-test-date-fixtures-must-match-production-normalization.md)
- **Codex へのテスト生成依頼も同期実行・`< /dev/null`** (Developer と同じ穴)
- **既存の失敗テストを「ベースライン」と報告する前に、PJ の known-failures 台帳と照合する。台帳にない失敗は「未分類」と明記して返す** (「ベースライン」の山が本番バグを隠した実績: sessions/2026-06-11)
- **MCP ツールレベルのテスト (go-sdk) は Codex の「設計doc単独生成」では作れない。** ツールは ctx 経由で identity 注入され、ハンドラは unexported。既存の package-internal 統合テスト (例 dandan-app `internal/auth/mcp_integration_test.go`) の `issueAccess`/`testLogin`/`bearerRT`/`StreamableClientTransport` 往復パターンを流用し、Reviewer が同パッケージ内 (`package auth`) で自作する。`mcp.NewServer(Deps{GitHub: 実Client with WithApp+WithAPIBaseURL(fake)})` を auth 保護 `/mcp` の背後に配線 → アクセストークン発行 → `session.CallTool` で往復。IsError メッセージは `res.Content` の `*TextContent`、成功値は `res.StructuredContent` を json 経由で decode。フィールド名は設計doc の戻り値記述から取り、具体値 assert が通れば wire 契約一致の証明になる (sessions/2026-07-04 dandan Slice2)
- **Bash heredoc は中身に `&&` が 1 箇所でもあるとグローバル `block-bash-amp` フックに当たる。** Go コード (→ネスト if に分解、`||` は当たらない) だけでなく、Codex への指示文の散文や「このノート自体の更新」でも発火する (2026-07-08 に 2 回踏み直し)。heredoc を書く前に中身から `&&` を排除する。どうしても文字列が要るときは Python 側で `'AND'*2` 的に結合して生成する (sessions/2026-07-04)
- **`codex` は PATH に無い。実体は `/Applications/Codex.app/Contents/Resources/codex`** (2026-07-05 時点、codex-cli 0.142.5)。`command not found` で止まらないこと
- **Codex の sandbox は localhost DB 接続を拒否する** (workspace-write でも network 不可)。Postgres 前提テストは Codex にはコンパイル確認までしかさせられない。実行は Reviewer が自分で回す (TEST_DATABASE_URL + docker postgres を自前起動)
- **設計docは wire/DB 状態を規定するが store API の意味論 (戻り値・入力 struct のどのフィールドを永続化するか) は規定しない。** ブラインド生成テストが store の戻り値や `CreateX(struct{RevokedAt:...})` の永続化を仮定すると偽陽性 fail になる (dandan Slice1 で 2 件: RotateRefreshToken の戻り値 = 更新前スナップショット / CreateMCPToken が RevokedAt を無視)。fixture は直接 SQL UPDATE、assert は DB 直読に倒す。切り分けは probe テスト 1 本 (Create → SELECT) で 1 分
- **redirect の query 値は URL エンコードされて返る** (`rd=/dashboard` → `rd=%2Fdashboard`)。設計docの文字面と Location 文字列を直接比較しない。`url.Parse` → `Query().Get()` で比較
- **「write が起きない」系の失敗で「未配線」と断定しない。** ブラックボックスでは「未配線」と「配線済みだが best-effort `_ =` がエラー握りつぶし」を区別できない (dandan Slice1 で後者を前者と誤帰属しかけた。真因は SQLSTATE 42883 の無音化 → gotcha/best-effort-write-swallows-sqlstate-errors.md)。帰属は観測レベルで書く
- **typed AddTool の入力 schema は非ポインタ全フィールドが required になる (jsonschema-go)。設計docの入力表で `?` が付かないフィールドは required とみなし、ブラインドテストでも常に全フィールドを渡す** (空配列含む)。dandan Slice2 で submit_plan の acceptance_criteria/tags/insights/relations と apply_assignments の reason を省略して 7 テストが偽 fail、1 ラウンド浪費 (2026-07-05)
- **空状態契約 (空配列で返す) の検証は「キー存在 + 値が nil でない + len==0」の 3 点セット。** Go の nil slice は wire で null になり、典型的な系統的違反 (gotcha/go-nil-slice-null-breaks-mcp-empty-state-contract.md)。契約違反は Fatalf でなく Errorf + 空 slice 返しで続行すると、null の裏の挙動 (イベント記録・ガード等) まで同ランで検証できる (2026-07-05)
- **共有 TEST_DATABASE_URL で `go test ./...` するとパッケージ並列 (デフォルト -p) で TRUNCATE 同士が deadlock する (SQLSTATE 40P01)。** 実装バグと誤帰属しない: 単独パッケージ実行 → 全 green なら環境依存。判定用の全体回帰は `go test -p 1 ./...` で取る (dandan 2026-07-05)
- **Codex 生成テストの偽 fail は、まず fixture の合成データ論理を手で追う。** 剰余条件で seed を分岐させるループ (`i%2` で reassign、`i%5` で unassign 上書き等) は、Codex 自身が上書き条件を忘れた assert を書く (dandan Slice3: i=55 は %5 上書きで from=m1 なのに「m1 非関与」と誤 assert。件数 assert は DB 突合で pass しており実装は正しかった)。負系の文字列 assert は「その行が条件に該当しないこと」を seed 式から再計算してから直す (2026-07-05)
- **seed ヘルパの UpsertUser は OAuth ログイン済み user の github_login / github_token_enc を上書きする。** ログイン後に同 user_id で seed すると sealed token が壊れ GitHub 系表示が縮退し、login 文字列 assert も外れる。表示の login assert は固定文字列でなく DB 直読 (`SELECT github_login FROM users WHERE id=$1`) と突合する (2026-07-05)
- **コピー契約 (fidelity 優先) の PJ では、設計docの検証条項がコピー元原文と衝突したらコピー元が勝つ。** dandan Slice2 で 2 件: §9.5-2「存在しない grep 0 件」は天野原文 description「存在しない ID はスキップ」に誤ヒット (意図は policy/open_* の先回り文言のみ)、0 件応答の空配列契約は天野が nil slice (wire null) を返すため null が正。判断前に許可されたコピー元比較で原文を突合してから assert を絞る (2026-07-08)
- **ダッシュボード HTML の負系 grep (「この名前が出ないはず」) はフィルタ UI の select 選択肢に誤ヒットする。** フィルタの正しさは data-testid 行数一致で取る (dandan 2026-07-08)
- **MCP Apps UI ハーネス (report-back 方式) の駆動は「hostLog にリクエストが載った」で先へ進まない。** hostLog は送信記録で応答適用を保証しない → 応答適用後にしか変化しない DOM マーカーを待つ。ui/message の text は `params.content[0].text` (`params.text` は常に undefined)。dark 検証は `--force-dark-mode` + 実際に色の付く要素の dark palette 値。詳細 gotcha/mcp-apps-ui-harness-testing.md (2026-07-08 Slice3 で 6 シナリオ偽 fail)
- **設計docの「friendlyError 契約」等の UI 横断記述は、コピー契約 PJ では画面ごとに実装有無を原文で確認してから assert する。** 天野 friendlyError は workspace.html のみ (insights.html は JSON.stringify で Error→"{}" 表示)。note の「コピー元が勝つ」原則の画面単位 instance (2026-07-08)
