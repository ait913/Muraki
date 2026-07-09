# Developer の職業的習慣ノート

召集されたら最初に読む。**過去の自分 (歴代 Developer) が実際に踏んだ穴**であり、予防的な網羅ルールではない。新しく踏んだら自分で追記・置換する (INDEX 対象外、再生成不要)。

- **Codex は同期実行のみ。バックグラウンド委譲・「監視タスクを設置した」報告で終了は禁止。** subagent が終了すると Codex プロセスは孤児化し実装が途中で止まる。完了まで待ってから報告する (再発4回: sessions/2026-06-02 ×2, 2026-06-08, 2026-06-11)
- **`codex exec` をパイプ/リダイレクト付きで走らせる時は `< /dev/null` 必須。** stdin 待ちで 30 分ハングした実績 (tool-quirk/codex-exec-background-needs-dev-null-stdin.md)
- **完了報告の前に worktree 内で typecheck / build を自分で走らせて pass を確認する。** 「Codex が完了と言った」は完了ではない。NodeNext 50+ エラーを Leader の pre-flight で初めて発覚させた実績 (sessions/2026-05-26)
- **researcher の version 列挙を無検証で package.json に転記しない。** install が通ることまでが自分の仕事。架空 version で `npm install` 全滅の実績 (sessions/2026-05-26)
- **`codex` が PATH に無いことがある (cask 実体が消える)。** `which codex` 失敗時は `/Applications/Codex.app/Contents/Resources/codex` を直接叩く。Caskroom の version dir が空でも app bundle 内に本体がいる (2026-07-04)
- **Go の自己検証は `go -C <worktree> build ./... ; go -C <worktree> vet ./...` で。** Bash tool は呼び出しごとに cwd をリセットするので、worktree 外から `go build ./...` すると "directory prefix . does not contain main module" で誤って fail に見える。`cd` は permission prompt を招くので `-C` フラグを使う (2026-07-04)
- **並走 slice で依存ファイル未存在のままフルビルド不能な時は、scratchpad に worktree をコピーし「仮定した契約」のスタブ (別ファイル名) を足して `go -C build/vet` で typecheck する。** worktree 本体にスタブを置くとマージ時に衝突するので絶対に置かない。「gofmt が通った」だけで報告しない (2026-07-05, dandan-app Slice2)
- **`go build`/`go vet` green は SQL の実行時エラーを一切捕まえない。** pgx で `$n - interval '...'` と書くと Postgres が `$n` を interval に型推論して 42883 (operator does not exist) になる — `$n::timestamptz` の明示キャストが要る。しかもエラーを `_ =` で握りつぶす best-effort 系 (last_used_at touch 等) だと本番でも沈黙する。DB を触る Slice は、実 PG が手元にあるなら 1 回スモークしてから報告する。Reviewer の「呼んでいない」診断も実際は「呼んでいるが SQL が死んでいた」だった — 帰属は計測 (エラーを一時的に stderr へ) で確定してから直す (2026-07-05)
- **codex sandbox はネットワーク不可 = localhost の DB 接続も `httptest` の listen も落ちる。** `go test` が `connect: operation not permitted` / `bind: operation not permitted` で fail しても実装バグではない。DB 依存テスト・ローカル起動確認は Codex に任せず Developer が worktree 外で自分で回す。同理由で vendored 資産 (htmx 等) の DL も召集前に済ませる (2026-07-05)
- **Codex をバックグラウンドで走らせても turn を「待機中」で終えない。poll で待ち切って報告まで出す** (2026-07-05, 07-08 に2回発生)
- **goose の SQL migration で `DO $$ ... END $$;` ブロックは `-- +goose StatementBegin` / `-- +goose StatementEnd` で囲まないと "unterminated dollar-quoted string" で実行時死する。** go build/vet では捕まらない。migration を書いた Slice は goose CLI (`go install github.com/pressly/goose/v3/cmd/goose@latest`) + 実 PG で Up/Down/Up を回してから報告する。Down も「新スキーマで合法になったデータ (unique 撤去後の重複行等) が旧制約の再作成を 23505 で壊さないか」まで見る (2026-07-08, dandan-app Slice1)
- **Codex は「可能な範囲でテスト移植」を「移植ゼロ + 理由書き」に倒しがち。また「不変」契約の additive ツールでも文言を勝手に簡略化する。** テスト移植は配置先・流用ハーネス・skip 条件まで指定した専用ラウンドに分け、「不変」資産は完了後に旧実装と文言レベルで diff 突合する (2026-07-08, dandan-app Slice2: check_repo のメッセージ書き換えと天野テスト移植スキップを round 2 で回収)
- **headless Chrome の `--dump-dom` + `--virtual-time-budget` は、ページが timer や fetch を回し続けると Chrome が終了せず `cmd.Output()` が永久ハングする** (go test 600s タイムアウトで発覚)。UI スモークは「ページ側から fetch で Go 側の /report にログを POST → テストは poll して成立で `exec.CommandContext` を cancel (kill)」の report-back 方式にする。Chrome の自然終了に依存しない (2026-07-08, dandan-app Slice3 uihost)
