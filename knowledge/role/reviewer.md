# Reviewer の職業的習慣ノート

召集されたら最初に読む。**過去の自分 (歴代 Reviewer) が実際に踏んだ穴**から蒸留した現役の習慣 (20 本以内を維持)。新しく踏んだら自分で追記・置換し、古びたら捨てる (INDEX 対象外、再生成不要)。2026-07-31 に Opus 5 移行で全面圧縮 (原本: ai-audit/archive/20260731-muraki/role/reviewer.md)。

1. **negative control (負のコントロール) は「バグ修正系のリリースゲートでは標準」。** 修正前コード (`git show <merge-base>:<file>`、未コミットなら召集時の `cp`/`tar` バックアップ) に戻してテストが落ちることを確認してから GREEN を出す。「テストが実装に迎合していないか」はこれだけが証明できる (sessions/2026-06-11)。全レビューでの一律義務ではない — 軽量パスでは要求しない
2. **変異は「届いたこと・向き・入口」を証明する。** site 数を `grep -c` で数えて置換数と突合し (2 site 目が生き残る)、ガードを弱める向きに当て (`or true` で包むとパラメータ数を保てる)、公開 API から最初に通る site に当てる (helper 側は早期 return に隠れる) (2026-07-17/30)
3. **負のコントロールで生き残ったテストは 1 本ずつ説明する。** 「殺せなかった本数」を説明できて初めて完了。TZ シフト等の変異はシフト窓に標本が無いと原理的に検出できないので、境界窓の標本は自分で足す (2026-07-17, atender)。「赤くならなかった」はテストの無力の証明という成果 — そこで止めず実経路を踏む別レイヤのテストを新設して赤→緑まで示す
4. **偽 fail の第一容疑者は自分のハーネス。** 全シナリオが同じ異常値なら fixture・起動待ち・ルーティング・mock の shape (W3C エラー型の定数プロパティ / RTL の cleanup 忘れ / エポック手計算) を先に疑う。mock の shape は既存 fixture ヘルパから採り、手打ちしない (2026-07-16)。WS ライブラリ (`coder/websocket` 等) は「呼び手の ctx timeout でも接続を閉じる」契約のものがある — 短命 ctx で `Read` をポーリングすると自分の Read が接続を壊し「サーバーが早期切断した」ように見える偽観測になる。1 コネクション 1 回の長い block Read で検証する ([[gotcha/coder-websocket-short-lived-read-context-closes-connection]]、2026-08-21 bloom P3c)
5. **偽 RED / テスト全滅は本番経路の直接プローブで切り分け、帰属は観測レベルで書く。** ブラックボックスでは「未配線」と「配線済みだがエラー握り潰し」を区別できない — 断定せず観測を書く (sessions/2026-06-11)
6. **ベースラインは台帳と照合し、台帳に無い失敗は「未分類」と明記する。** 台帳は「測った日 + コミット + failure 数」まで要求し、実測と食い違ったら実測を正として台帳をその場で置換する (sessions/2026-06-11, 2026-07-16)
7. **召集されたら最初に「テストが 0 本ではないか」を見る。** 削除されたテスト + `[no test files]` + exit 0 = 中身ゼロの緑。`passWithNoTests` や include の glob ずれも同じ vacuous green を作る (2026-07-30, omatase)
8. **実装を読まずにシグネチャだけ採る手段を持つ:** `go doc` / swiftmodule strings + `swift-demangle` / `tsc --declaration --emitDeclarationOnly` / **Dart は `dart doc --output <scratch>` → 生成 HTML から機械抽出** (クラス・enum 値・定数実値・provider 宣言まで採れる。bloom P2b で全面使用) / 空 `{}` から始める自己発見 decode プローブ / 稼働中 API へのブラックボックス probe。blind を保ったままコンパイルが通るテストが書ける (2026-07-17〜30, 2026-08-20)
9. **設計が規定しない意味論 (store の戻り値・永続化されるフィールド・寛容/厳格の別) を仮定しない。** fixture は SQL 直挿入・実ログインフロー・実 API 採取で作る。「body で受け取らない」は 400 拒否でも 200 無視でも満たされる — status を決め打つと偽 RED (2026-07-05〜23)
10. **設計 doc 内の矛盾 (例示 vs 規範 / 表の値 vs 生成規則) は規範・挙動仕様節を正としてテストし、食い違い自体を報告する。** 「回帰なし」「現行と同一」条項の期待値は設計の文面でなく merge-base の実測から採る (2026-07-29/30, atender)
11. **wire 契約は「同じ値」でなく「形」まで assert する。** serialization の形 (`Z` サフィックス)、error 封筒の `code`/`message` 実値、「キー存在 + 非 null + len」の 3 点セット。status だけの assert は封筒違い・null 化を素通しする (2026-07-05〜30)
12. **ポリシー定数をテストにリテラルで焼かない。** 定数を import して `MIN±1` から導出する。焼くと定数を上げたリリースで必ず陳腐化する (2026-07-29, atender)
13. **手元 TZ に寄生した緑を疑う。`TZ=UTC` で 1 回掃引する。** 端末ローカル暦が仕様である側は「TZ 非依存の標本」と「TZ gate 付き逐語標本」の 2 系統に割る (2026-07-17/30)
14. **in-process テストの原理的な穴は判定に明示する。** Vitest は CJS/ESM interop バグを検出できない (子プロセス probe が唯一の担保)。hook に癒着したロジック・View の `.task` 配線は純関数の緑では 1 ミリも証明されない。「カバーできていない挙動」を GREEN の中に書く (2026-07-16/17)
15. **検証で環境を壊さない。** 書き換えたら `cp` バックアップ → バイト単位復元。`git checkout --` は Developer の未コミット実装を HEAD に戻して消す。変異注入は使い捨て detached worktree で回す (途中で異常終了しても本番の木が無傷)。dev の `.env` の値は dev として正しいので「直して」放置しない (2026-07-17/30)
16. **「テストがあるか」でなく「テストがその配線を実行するか」を見る。** DTO 層と client 層が個別に緑でも、両者を繋ぐ `as:`/型引数/実経路は無テストのことがある (2026-07-17, atender)
17. **UI 検証は assert を書く前に実体を採る。** `app.debugDescription` を 1 回吐く / pixel assert は対象色が実際にビットマップに出るか probe してから書く。判定はフラグ・スクショの名前 (`_ok=true`) でなく中身 (byte hash / pixel 計数 / 2 候補値のどちらに近いか) で行う。flaky 疑いは同一コードで 2 回回して顔ぶれを比較してから regression を語る (2026-07-17〜30)
18. **GREEN を束ねない。** 「修正が効いたと証明できた件」と「非退行しか言えない件」を割って報告する。手動確認送りにした境界も明示する (2026-07-30, atender)
19. **subagent が API エラーで死んでも SendMessage で再開して報告だけ回収できる (「ファイルを変更するな」を明示)。異常終了したら報告を読む前に `git diff` を確認する** — 変異や中途変更が木に残っていることがある (gotcha/mutation-testing-agent-crash-leaves-mutation-in-tree.md)
20. **実装が設計に忠実でも、失敗の帰属先が設計の不備なら設計の不備として報告する。** 「実装 or 設計」の切り分けまでが判定 (2026-07-16, omatase)
21. **成功応答だけの dio/fetch capture テストで満足しない — エラーコード分岐のある設計 (409/403/410 等) では最低 1 本、意図的に非 2xx を注入する負のコントロールを書く。** Dio は `validateStatus` 既定 (2xx のみ成功) のまま非 2xx を返すと、独自エラー封筒→例外変換ロジックより先に生の `DioException` を投げる。P2b の成功系テストでは気づけず、P3 で初めて発覚 ([[gotcha/dio-default-validatestatus-swallows-custom-error-envelope]], 2026-08-21 bloom)。**dart doc で Implementation セクションが出るのはトップレベル `final` 変数 (Riverpod provider の初期化式など) だけ** — インスタンスメソッドの本体は出ない。前者を読むと実装ロジック (route 定義等) が意図せず見えるので、シグネチャ取得用途では Constructors/Properties/Methods の一覧に留め、Implementation ブロックの多用は避ける

**Codex を使う場合は `knowledge/tool-quirk/codex-behavior.md` を必読。**
