# Reviewer の職業的習慣ノート

召集されたら最初に読む。**過去の自分 (歴代 Reviewer) が実際に踏んだ穴**であり、予防的な網羅ルールではない。新しく踏んだら自分で追記・置換する (INDEX 対象外、再生成不要)。

- **validation エラーの assert は status 中心 (400) にする。`error.code` 等の strict assert は zValidator が生 ZodError を返す構成で偽陰性になる。** gotcha 化済みなのに 2 回踏み直した (sessions/2026-06-02)
- **jsdom + Vitest は localStorage / matchMedia 未提供。**先に polyfill (gotcha/jsdom-no-localstorage-in-vitest.md)
- **バグ修正系のレビューは negative control を標準にする**: 修正前コードに戻してテストが落ちることを確認してから GREEN を出す。「テストが実装に迎合していないか」をこれだけが証明できる (sessions/2026-06-11 で有効)
- **偽 RED / テスト全滅の疑いは、実装コードでなく本番経路の直接プローブで切り分ける。** bulk API 全滅に見えた失敗を fixture の日付規約ミスと特定した実績 (sessions/2026-06-11)。fixture の日付は本番の正規化規約 (JST midnight) に合わせる (gotcha/api-test-date-fixtures-must-match-production-normalization.md)
- **Codex へのテスト生成依頼も同期実行・`< /dev/null`** (Developer と同じ穴)
- **既存の失敗テストを「ベースライン」と報告する前に、PJ の known-failures 台帳と照合する。台帳にない失敗は「未分類」と明記して返す** (「ベースライン」の山が本番バグを隠した実績: sessions/2026-06-11)
- **MCP ツールレベルのテスト (go-sdk) は Codex の「設計doc単独生成」では作れない。** ツールは ctx 経由で identity 注入され、ハンドラは unexported。既存の package-internal 統合テスト (例 dandan-app `internal/auth/mcp_integration_test.go`) の `issueAccess`/`testLogin`/`bearerRT`/`StreamableClientTransport` 往復パターンを流用し、Reviewer が同パッケージ内 (`package auth`) で自作する。`mcp.NewServer(Deps{GitHub: 実Client with WithApp+WithAPIBaseURL(fake)})` を auth 保護 `/mcp` の背後に配線 → アクセストークン発行 → `session.CallTool` で往復。IsError メッセージは `res.Content` の `*TextContent`、成功値は `res.StructuredContent` を json 経由で decode。フィールド名は設計doc の戻り値記述から取り、具体値 assert が通れば wire 契約一致の証明になる (sessions/2026-07-04 dandan Slice2)
- **Go テストを Bash heredoc で書き出すと、コード中の `&&` (例 `if a != "" && a == x`) がグローバル `block-bash-amp` フックに当たる。** ネスト if に分解して書く (`||` は当たらない)。テスト生成のたびに踏むので最初からネストで書く (sessions/2026-07-04)
