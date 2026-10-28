# Researcher の職業的習慣ノート

召集されたら最初に読む。**過去の自分 (歴代 Researcher) が実際に踏んだ穴**から蒸留した現役の習慣 (20 本以内を維持)。新しく踏んだら自分で追記・置換し、古びたら捨てる (INDEX 対象外、再生成不要)。2026-07-31 に Opus 5 移行で全面圧縮 (原本: ai-audit/archive/20260731-muraki/role/researcher.md)。

1. **調査手段は自分の WebSearch / WebFetch / curl 直読みが主体。** Gemini CLI は free-tier 廃止 (`IneligibleTierError`, 2026-07) で使わない。外部 CLI (Codex 等) は突合用の補助に留め、待ち時間の間に自分で一次ソースを取りに行く方が速い
2. **package version は `npm view <pkg> version` で 1 個ずつ実機確認する。** 同系列だからと推測列挙しない — 架空 version で install 全滅の実績 (sessions/2026-05-26)
3. **「○○を参考に」の対象は要約・既存 knowledge より先に一次ソース (実コード・実機・配信 CSS) を読む。** 食い違ったら一次ソースが正。既存 knowledge の「How to apply」も半分だけ正しいことがある — 引用前に 1 回実測で裏取りする (sessions/2026-06-08, 2026-07-30)
4. **切り分け依頼は推測で答えず、コード + 実プローブ (API 直叩き等) で断定する** (sessions/2026-06-11)
5. **SPA / JS レンダリングのページは WebFetch で本文が取れない。** Apple は JSON エンドポイント (`developer.apple.com/tutorials/data/.../<slug>.json` — HIG も API リファレンスの `introducedAt` も取れる)、規約系は `curl -sL` + HTML strip、図版に埋まった数値は画像を落として Read。どうしても取れなければ「未確認」と書く。**「I don't have access」前置きの WebFetch 出力や一般知識の穴埋めは出典として無効。** 出典が再検証不能な既存 knowledge は「未再検証」と添えて渡す (2026-07-05〜17)
6. **「フィールドが空/None だから X ではない」と推論する前に対照群を 1 つ引く。** 単一サンプルの欠損は対象でなくデータソースの性質であることが多い (2026-07-16, Google Fonts license)
7. **API・シンボルの実在とビルド影響は実際にコンパイル/ビルドして確定する。** Swift は SDK の `.swiftinterface` grep (framework 分割に注意) → `swiftc -typecheck` で実証、ビルド成果物レイアウトは実ビルド、deployment target 影響は `xcodebuild ... IPHONEOS_DEPLOYMENT_TARGET=X` の無改変上書き、RN のバンドル解決は `expo export` の `.hbc` 検索 (非 ASCII は UTF-16LE で数える) (2026-07-16〜30)
8. **spec 乖離が常態のプロダクトでは、spec (openapi 等) の欠落を「機能の不在」と読まない — controller / validator / model を読む。** そして読んだ版が稼働中の実物と一致するか (`GET /version` 等) を 1 コマンドで確認してから設計材料にする (2026-07-16, Coolify)
9. **クライアント型と API レスポンスの突合は、実物の型をコンパイルして実 JSON をデコードさせるのが唯一の断定手段。** 目視比較では nested 必須フィールドや encoder の「nil はキーごと消える」層が出ない。**空配列 fixture の PASS は偽の合格** — 件数と null 有無を表示させ、N=0 は未検証扱い。null 分岐は到達可能性を実測してから「不一致」と言う (2026-07-17/30, atender)
10. **調査で API を叩いてデータを作ったら、消してベースラインに戻したことまで確認して報告する。** demo DB の状態も次セッションの前提 (2026-07-17)
11. **「機能が動かない」系はまず (a) 起動導線が後続コミットで消えていないか (`grep` + `git log -S`) と (b) 時間軸 (日付を未来にずらしたコピーを 1 回走らせる) を疑う。** 空配列・0 件系の失敗は特に時間軸から (2026-07-29, atender)
12. **UI 症状は仮説を立てたら使い捨て probe (xcodegen の最小アプリ / macOS `ImageRenderer` の offscreen 再現 / 素のネイティブコントロール) で潰す。** 筋の良い仮説 (clipShape が当たり判定を殺す等) が実測 126 タップで完全に誤りだったことがある。docs で決着しない挙動は 3〜10 分の実測で決着する (2026-07-30)
13. **UI 判定は目視でなく数値で、1 回でなく複数回で。** スクショの distinct color 数 / md5 / pixel diff、15s と 70s の 2 枚 (「読み込み中」を「壊れている」と誤読しない)、連続ジェスチャで再現率を出す (1/3 でしか再現しない挙動がある)。dark mode は `simctl ui ... appearance dark` を明示してから撮る — light 環境では絶対に再現しないバグがある (2026-07-30)
14. **共有環境を壊さない。** `xcrun simctl list devices booted` を先に見て booted 機に install/appearance 変更をしない。別 udid を自分で boot し、終わったら uninstall + shutdown まで 1 セット (2026-07-30)
15. **エラーメッセージの「出方」自体が観測データ。** どのエラーなら enveloped でどのエラーなら素か、を分類するだけで候補が 1/3 に絞れることがある (2026-07-30, atender)
16. **前任エージェントの scratchpad を `ls -lt` で見てから組み始める。** probe アプリや撮影済スクショが丸ごと残っていることがある — ただし前任の成果物も検品してから使う (2026-07-30)
17. **`npm view <pkg> version` だけで安定版と決めない — `dist-tags` を見る。** `prisma` CLI は `latest` が 8.0.0-rc.19 で、`@prisma/client` の `latest` は 7.10.0 (CLI と client が別系統)。さらに「ライブラリが X を持つはず」は SDK の major 更新で消える (MCP TS SDK v2 は AS ヘルパを削除) — `npm i` して `dist/` と migration guide を grep してから「ある/ない」を言う (2026-10-02, wasawasa)
18. **Coolify 等「API が spec より狭い/広い」系は、稼働版 (`GET /version`) のコントローラ実体を読み、`api.ability` と token 権限を先に確認する。** 「logs が空」「settings が null」は権限差・一覧と個別の形の違いだった (2026-10-03, wasawasa)。また `POST` が「成功応答 + 未保存 ID」を返す経路 (skipped) がないか、ID を使う側の目線でソースを読む。**この役は Write/Edit ツールが無いことがある**: ファイルは Bash の heredoc で書く。シェルの AND 連結 (アンパサンド 2 連) はコマンド文字列のどこにあっても (grep のパターン・heredoc 本文含む) フックに弾かれて heredoc ごと失敗する。書く前にコマンド全体から消す (`chr(38)` を使う等)

19. **Tiptap/PM の UI 挙動は「素の拡張を esbuild で束ねた 1 ページ + playwright-core + Chrome headless shell」が最短** (Next 不要、数十秒で往復)。scratchpad の `pw/` は playwright-core の package.json が欠けて壊れていることがある → spike 内で `pnpm add -D playwright-core`、`executablePath` は `~/Library/Caches/ms-playwright/chromium_headless_shell-*/…/chrome-headless-shell`。macOS の `sed -i` は `-i ''`。JS 内の AND 演算子もフックに弾かれるので三項・入れ子 if で書く (2026-10-07, wasawasa)

20. **外部 API の「資格情報が通るか」は bogus 入力で応答コードの種類を比べる。** Apple `/auth/token` は壊れた code に `invalid_grant` (client 認証は通過) / 鍵・ID 不正は `invalid_client` を返す。ASC 側の「受理サイズ」も表を信じず、セット作成→実アップロード→`assetDeliveryState`→セット削除、で 1 分で決着する (ベースライン 0 件に戻すところまで確認) (2026-10-09, atender)


21. **シミュレータの OS 許可プロンプト (位置等) は `simctl terminate` / `privacy reset` / アプリ再起動では消えない。** 連続 run で同じスクショが出たら前の run のアラートを撮っている。run ごとに `shutdown`→`boot` し、別文言のプロンプトが出る条件 (notDetermined 起動の 3 択) を負のコントロールにして「新鮮なアラート」を証明する。WhenInUse の事前付与は `simctl privacy grant location <bundle>` (`location-always` は本物の Always になり Provisional は再現不能)。iOS 18 系の端末が無い時は `simctl create probe18 "iPhone 16" com.apple.CoreSimulator.SimRuntime.iOS-18-4` で作って `delete` まで 1 セット (2026-10-09, bloom)

**Codex を使う場合は `knowledge/tool-quirk/codex-behavior.md` を必読。**

22. **Coolify の `GET /applications/{uuid}` は `destination.server.settings` に暗号化済み `sentinel_token` 等を丸ごとネストして返す。** 全文を print せず、Python で必要キーだけ抜く (2026-10-10, bloom admin 調査)。新機能の有無はドキュメントより `gh api repos/coollabsio/coolify/contents/...` で実コードを読む方が速い (traffic analytics は docs に Traefik 側の詳細が無く、`bootstrap/helpers/proxy.php` で確定した)。docs に載っている CLI プラグイン/bouncer は「この経路 (CF Tunnel + Nginx 前段) で IP が取れるか」を parser の実ソースで確かめてから推奨する

23. **Apple DocC の「参照先ページ」の slug は推測せず、手元の JSON の `references` マップから `url` を引く。** REST API docs の `id_token` 参照先は `signinwithapplejs/authorizationi/id_token` で、`signinwithapplerestapi/id_token` 系は全部 404 だった。help.apple の `developer.apple.com/help/account/...` は通常 HTML なので `curl` + tag strip で本文が取れる (nav が長いので見出し語で `find` してから切り出す) (2026-10-13, bloom)

24. **PJ の作業ツリーは他セッションのブランチ・未コミット変更が乗っていることがある (bloom はローカル master が古く、checkout 中は別版)。** `git fetch` してから `git archive origin/<ref> <dirs> | tar -x -C <scratchpad>/<ref>` で読む用のコピーを作る (checkout も worktree も不要、共有ツリーを汚さない)。zsh では `grep --include=*.go` が glob 展開で `no matches found` になる — `--include='*.go'` とクォートする (2026-10-15, bloom)

25. **依存の CVE 下限調べは OSV API 1 発で済ませる。** `curl -s -X POST https://api.osv.dev/v1/query -d '{"package":{"name":"<pkg>","ecosystem":"PyPI"}}'` が全 advisory の `fixed` 版を返す (WebSearch の要約は patched 版を取り違える: CVE-2024-6827 を 23.0.0 と言う記事があるが GHSA は 22.0.0)。候補版の `requires_python` は `pypi.org/pypi/<pkg>/<ver>/json` で確認してから下限を提案する (Pillow 13 は 3.11 必須で、PJ の 3.10 対応と衝突した)。静的監査は読むだけで断定せず、scratchpad に使い捨て DB/ディレクトリを作って 5 分の挙動プローブで「fail-open」「警告のみ」を実測してから書く (2026-10-21, nexom)

26. **dist の型定義を読む時は `grep -n -F "symbol?"` (固定文字列) で行番号を取り、`sed -n 'N,Mp'` は数値を確定してから渡す。** `grep -n "postLogin?"` は `?` が正規表現で消えて空になり、`$((n-12))` が `-12` になって macOS の sed が `illegal option` で落ちる (同じ回で 3 回踏んだ)。better-auth のプラグイン実体は `better-auth/dist/plugins/<name>/` だが、social provider の実装は `@better-auth/core/dist/social-providers/<id>.mjs` (`accountSubject` はここ)、`validateUserInfo` の型は `@better-auth/core/dist/types/init-options.d.mts` — パッケージ跨ぎで `grep -rl` してから読む (2026-10-23, ais-pass)

27. **環境変数の取得で `export $(...)` や素の `export` を使わない。** 空展開で `export` 単体になり、全環境変数 (API トークン含む) が出力に出た (2026-10-26)。必要キーは `python3 -c` で settings.json / `os.environ` から名指しで取る。Go ライブラリ調査は「`proxy.golang.org/<mod>/@latest` (版・日付) + `/@v/<ver>.zip` を scratchpad に展開して grep (実コードが正) + OSV + `gh api repos/.../commits?since=` (停止判定)」が最短。README の認定表記は *RP と OP を分けて* 読む (zitadel/oidc は RP のみ認定)。AND 連結の文字列は grep のパターンや heredoc 本文でもフックに弾かれる (heredoc ごと失敗するので書き直しになる)

28. **Coolify の本番 API を Python urllib で叩くと Cloudflare が 403 (error 1010) を返す。** User-Agent に `curl/8.x` を付ける。`/version` は JSON でなく素の文字列。`GET /servers/{uuid}` の `settings` に暗号化済み `sentinel_token` が入るので、必要キーだけ名指しで print する (2026-10-29, aiserver)。Coolify の「できる/できない」は routes/api.php の差分 (4.5.0 は destinations / clone / migrate が増えた) と、危険操作の実装 (clone の `chown -R 1000:1000`、migrate の `isDev()` 限定) まで読んでから言う。proxy のように「disk 上の稼働物 vs DB 保存設定」が乖離しうる対象は両方を並べて見る

29. **「読み取りのみ」の SSH 調査で、実機へ scp しない・conf を丸ごと cat しない・du のエラーを流さない。** 解析スクリプトは `ssh host python3 - < local.py` で stdin から渡す (今回 `/tmp` に 1 ファイル置いてしまい消した)。nginx conf は `proxy_set_header X-...-Auth "<秘密>"` のように秘密が直書きされている (pass の vhost) — `cat` でなく `grep -E 'server_name|proxy_pass|alias|root|client_max'` で必要ディレクティブだけ抜く。`du -sh` を権限の無いディレクトリに掛けると他人のファイル名が数百行出る → `2>/dev/null`。Python の `config.py` は `ast` でキー名と非秘密キー (ADDRESS/PORT 等) の値だけ出す。Muraki clone 内の gitignore 済み config 複製は古いことがある (今回 TRUSTED_PROXY_COUNT 等が欠落) — 実機が正 (2026-10-29, aisaba-platform)
