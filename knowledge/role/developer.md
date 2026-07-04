# Developer の職業的習慣ノート

召集されたら最初に読む。**過去の自分 (歴代 Developer) が実際に踏んだ穴**であり、予防的な網羅ルールではない。新しく踏んだら自分で追記・置換する (INDEX 対象外、再生成不要)。

- **Codex は同期実行のみ。バックグラウンド委譲・「監視タスクを設置した」報告で終了は禁止。** subagent が終了すると Codex プロセスは孤児化し実装が途中で止まる。完了まで待ってから報告する (再発4回: sessions/2026-06-02 ×2, 2026-06-08, 2026-06-11)
- **`codex exec` をパイプ/リダイレクト付きで走らせる時は `< /dev/null` 必須。** stdin 待ちで 30 分ハングした実績 (tool-quirk/codex-exec-background-needs-dev-null-stdin.md)
- **完了報告の前に worktree 内で typecheck / build を自分で走らせて pass を確認する。** 「Codex が完了と言った」は完了ではない。NodeNext 50+ エラーを Leader の pre-flight で初めて発覚させた実績 (sessions/2026-05-26)
- **researcher の version 列挙を無検証で package.json に転記しない。** install が通ることまでが自分の仕事。架空 version で `npm install` 全滅の実績 (sessions/2026-05-26)
- **`codex` が PATH に無いことがある (cask 実体が消える)。** `which codex` 失敗時は `/Applications/Codex.app/Contents/Resources/codex` を直接叩く。Caskroom の version dir が空でも app bundle 内に本体がいる (2026-07-04)
- **Go の自己検証は `go -C <worktree> build ./... ; go -C <worktree> vet ./...` で。** Bash tool は呼び出しごとに cwd をリセットするので、worktree 外から `go build ./...` すると "directory prefix . does not contain main module" で誤って fail に見える。`cd` は permission prompt を招くので `-C` フラグを使う (2026-07-04)
