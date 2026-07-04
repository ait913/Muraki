# Researcher の職業的習慣ノート

召集されたら最初に読む。**過去の自分 (歴代 Researcher) が実際に踏んだ穴**であり、予防的な網羅ルールではない。新しく踏んだら自分で追記・置換する (INDEX 対象外、再生成不要)。

- **package version は必ず `npm view <pkg> version` で 1 個ずつ実機確認する。同系列パッケージだからと version を推測列挙しない。** 推測した `@tanstack/router-plugin@1.170.8` が npm に存在せず install 全 abort の実績 (sessions/2026-05-26)
- **「○○を参考に」と言われた対象は、要約・既存 knowledge より先に一次ソース (実コード・実機・配信 CSS) を読む。** 要約と一次ソースが食い違ったら一次ソースが正。既存 knowledge の「record に type を保存」誤記を実コードで訂正した実績 (sessions/2026-06-08)、一次ソース研究を飛ばして CF ダッシュボードを輸入し「センスがない」と却下された実績 (同)
- **切り分け依頼は推測で答えず、コード + 実プローブ (API 直叩き等) で断定する。** 「事実ベースで」の切り分けがデッドロックの単一真実を突き止めた成功例 (sessions/2026-06-11 #36)
- **`gemini -p` が `IneligibleTierError: This client is no longer supported... migrate to Antigravity` で落ちる時がある (2026-07)。CLI の free-tier 廃止。** その場合は WebSearch + WebFetch (公式 docs 直読み) + codex で代替。gemini 復旧を待たず即フォールバックせよ。加えて `codex` が PATH に無い環境もある (`command not found: codex`) — 事前に `which codex` で確認し、無ければ WebFetch/WebSearch で公式一次ソースを取りに行く
- **Apple HIG ページは WebFetch だと JS レンダリングで本文が取れず、モデルが一般知識で穴埋め回答してくる (出典として無効)。`https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<slug>.json` を fetch すれば実本文が取れる。** tab-bars で「アクセスできないが一般知識で答える」ハルシネーション回答を掴みかけた実績 (2026-07-05)。「I don't have access」系の前置きがある WebFetch 出力は出典として採用しない
- **developer.apple.com (HIG含む) は SPA で WebFetch では本文が取れない。`/tutorials/data/design/human-interface-guidelines/<slug>.json` を curl で直叩きする。** WebFetch 4連続空振りの実績 (2026-07-05)。詳細: knowledge/library/apple-developer-docs-json-endpoint.md
