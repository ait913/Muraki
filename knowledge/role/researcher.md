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

**Codex を使う場合は `knowledge/tool-quirk/codex-behavior.md` を必読。**
