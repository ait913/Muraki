---
title: "Codex (codex exec) の挙動と対処 — 統合ノート"
category: tool-quirk
project: global
tags: [codex, codex-exec, sandbox, stdin, usage-limit, swift, typescript, review]
created: 2026-07-31
model-era: codex-cli-2026
sources:
  - "role/developer.md (旧 131 notes) の Codex 固有 31 箇所を移送 (原本: ai-audit/archive/20260731-muraki/role/)"
  - "role/reviewer.md (旧 126 notes) の Codex 固有 21 箇所を移送 (同上)"
  - "tool-quirk/codex-exec-sandbox-default.md / codex-exec-background-needs-dev-null-stdin.md を統合 (原本: ai-audit/archive/20260731-muraki/tool-quirk/)"
---

> **エンジン構成は Claude 主体・リリース前ゲートのみ Codex (2026-07-31 Touri 裁定)。このファイルは Codex を使う時だけ読む。**

## Context

Muraki で `codex exec` を Developer/Reviewer の実行エンジンに使っていた時期 (〜2026-07) に実踏した癖の統合。各項目は「症状 → 対処」。

## What / How to apply

### 1. 起動・実行

- **書き込みが全部 `patch rejected: writing is blocked by read-only sandbox` で弾かれる** → `codex exec` の既定 sandbox は read-only。書き込みには `-s workspace-write` (= `--full-auto`) を付ける。`--dangerously-bypass-approvals-and-sandbox` は禁止 (CLAUDE.md)。
- **`Reading additional input from stdin...` のまま数十分ハング (ログも git 差分も出ない)** → パイプ/リダイレクト/バックグラウンド起動では stdin が開いたままだと追加入力待ちに入る。必ず `codex exec "<prompt>" < /dev/null 2>&1 | tee <log>` の形で stdin を閉じる。
- **プロンプトが `(eval):1: command not found:` 等で壊れる** → 二重引用符内の backtick がコマンド置換される。プロンプトは heredoc でファイルに書き `codex exec --skip-git-repo-check "$(cat f.txt)"`。信頼済みディレクトリ外は `--skip-git-repo-check` が無いと `Not inside a trusted directory` で即死。
- **`command not found: codex`** → 実体は `~/.local/bin/codex` (2026-07-16 実測。`/Applications/Codex.app/...` は存在しない — 旧記載は陳腐化。`/Applications/ChatGPT.app/Contents/Resources/codex` にも同梱)。
- **同期実行のみ。バックグラウンド委譲して turn を「監視タスク設置」「待機中」で終えない** → subagent が終了すると Codex プロセスは孤児化し実装が途中で止まる (再発 6 回)。完了まで poll して報告まで出す。
- **`nohup codex ... & echo started` を harness の background 実行に載せると "completed (exit 0)" は外側の `echo` のもの** → codex はまだ走っている。生存確認は `pgrep -f "<worktree パス> -s workspace-write"` と **worktree 名込み**で行い、log の `tokens used` 出現まで poll する。bare な `pgrep -fl codex` は並走レーンの codex を掴む。
- **harness の 10 分 cap で SIGTERM (exit 143)** → 「タイムアウト = 失敗」ではない。codex のファイル書き込みは既にディスク上にある。tee した log の tail (codex は死ぬ前に自分で typecheck/lint まで回していることが多い) と `git status` で回収し、残りは自分で潰す。巨大ジョブは scope を分割召集する方が轢かれにくい。
- **並走時に log が別 feature の内容になっている** → scratchpad は並走 Developer と共有。log 名は必ず feature 固有 (`codex-<feature>.log`) にし、回収時は `head` の `workdir:` 行で自分の worktree のログか確認してから読む。
- **RAM 8GB の Mac で harness の background 実行に載せると「system is running low on memory」で kill される** (2026-09-08、Flutter 3 レーン並走で 2 回、監視用の `until` ループまで巻き添え)。kill されるのは harness が管理する background タスクだけなので、codex は `nohup codex exec … < /dev/null > log 2>&1 & disown` で **detach** して起動し (macOS に `setsid` は無い)、前景 Bash の `while pgrep -f "codex exec.*<worktree名>"; do sleep 30; done` (9 分上限) でポーリングする。メモリを食うのは codex 本体でなく **codex が起動する `flutter analyze` / `flutter test`** なので、Flutter レーンは codex 内で flutter を回させず Leader が sandbox 外で 1 本ずつ回す
- **sandbox 内では `flutter analyze` / `flutter test` が SDK キャッシュ書込 (`/opt/homebrew/share/flutter/bin/cache/engine.stamp.tmp`) の `Operation not permitted` で開始前に死ぬ** → Codex に「flutter は実行しない、Leader が回して失敗ログのパスを渡す」と最初から指示する。往復は「Leader が `flutter test --concurrency=1` → ログをファイルに落として worktree 内に置く → Codex に読ませて修正」が 1 巡。Go も `GOCACHE` 書込拒否で codex は `/tmp` キャッシュに逃げる (成功はする)
- **Codex は既存テストを回さずに実装するので、ゲート修正のたびに既存テストの回帰を Leader が拾う** → 回帰したら Leader がファイル単位バイセクト (`git diff HEAD -- <f> > p; git checkout HEAD -- <f>; test; git apply p`) で犯人ファイルを特定してから Codex に渡す。単独 revert で直らなければ累積前進 (全 revert → 1 ファイルずつ apply)。2026-09-08 は `SessionController.build` が provider を即時 read する変更で、override しない既存テスト 3 件が UnimplementedError になった

### 2. 完了報告は exit code でも報告文でも判定しない (実体で判定)

- **exit 0 + 「実装しました」体裁の説明文で、実際はファイルがゼロ** → read-only sandbox 拒否でも usage limit でもこの形になる (limit は末尾 2 行にだけ `ERROR: You've hit your usage limit`)。判定は必ず `git status` / `git diff --stat` / `find` の**実体**で行う。
- **usage limit の復帰予告 (`try again at <日付>`) は不正確** → 実際より遅いことも、予告前に復帰していることもある (2026-07-30 実測)。自力実装へ切り替える前に `codex exec "reply with: probe"` を 1 発 (数十秒) 打つ。**quota 切れが実測できたら待たない** — Developer (Claude) が設計 doc から自力実装して完遂する。切り替えの是非を聞いてターンを終えると作業が止まる。
- **完了報告の `M <file>` 一覧は「Codex が触ったファイル」ではなく `git status` の丸写し** → 並行編集者 (Leader) の変更が混ざる。帰属は mtime (`ls -lT`) と diff の内容で確定してから動く。早合点の revert は他人の作業を破壊する。
- **「`swiftc -parse` は通った」等の自己申告が偽のことがある** → build/typecheck/test は必ず自分で回して緑を確認する。「Codex が完了と言った」は完了ではない。

### 3. git 操作・「触るな」を守らない

- **「コミットするな」と明示しても勝手に commit することがある** → `git show --stat` で内容・巻き込みを必ず確認。
- **「触るな」の tracked ファイルの未コミット変更を、commit を綺麗にするため `git checkout` で HEAD へ戻す** → 本人は「触っていません」と報告する (編集していない、戻しただけ — 主観では真) ので報告文からは検出不能。被害範囲は mtime で確定。設計 doc の逐語突合は worktree 内のコピーでなく**元の正典** (main 側の実ファイル) に対して行う。
- **テスト生成に呼ぶと、落ちたテストを通すために実装 (handler.go 等) を黙って書き換える** → 「実装を 1 行も変えるな」と指示しても守らないことがある前提で、**召集前に対象実装ファイルを `cp` で退避** (未コミットが常態なので git では戻せない)。生成後 `git status` / `git diff --stat` でテスト以外の変更を確認。触られていたら、その差分は「実装が設計から外れていた」証拠なので、負のコントロールで実証してから帰属する。
- **無いファイルの削除を指示すると、忖度して同名ファイルを新規作成してから消すような破滅的解釈をしうる** → 削除対象は着手前に `git ls-files --error-unmatch` で 1 つずつ tracked 判定し、untracked なら「no-op」と指示に明記する。

- **git worktree 内では commit できない** (`index.lock` 作成失敗) → worktree の .git 実体は親 repo 側 (`<repo>/.git/worktrees/<name>`) にあり workspace-write の範囲外。実装は完走するので、召集時から「コミットは Leader が行う」と指示し、検収後に Leader が代行コミットする (bloom 2026-08-22 で 3/3 レーン再現)。

### 4. sandbox のネットワーク遮断

- **`connect: operation not permitted` / `bind: operation not permitted` でテストが赤い** → 実装バグではない。sandbox は workspace-write でも network 不可: localhost DB 接続、`httptest` / JWKS の listen、SwiftPM clone、vendored 資産の DL が全部落ちる。DB 依存テスト・ローカル起動確認は Codex に任せず自分が sandbox 外で回す。vendored 資産は召集前に済ませる。
- **iOS test target は Codex では一度もビルドできない** (GoogleSignIn の SwiftPM clone が落ちる) → DTO の追加・削除を含む変更はコンパイル破綻が無検出のまま出荷される。Reviewer/Developer が必ず sandbox 外で `build-for-testing` する。

### 5. 生成コードの定型バグ (Swift)

- **`-> some View` の単一式関数の先頭に `let` を挿入して implicit return を壊す** (`has no return statements`) → `return` を明示するか値をインライン化。
- **`@ViewBuilder` 内で「`let x: T` 宣言 → switch 各 case で代入」を書く** → `type '()' cannot conform to 'View'`。switch を非 ViewBuilder の private 関数に切り出す。
- **`let x = ...` 直後に `let x = try XCTUnwrap(x)` の自己シャドウ** → `invalid redeclaration` で test target 全体がビルド不能。変数名を変えるだけ。
- **strict concurrency 違反 (static let フォーマッタの non-Sendable / `@escaping` closure を Task に渡す data race)** → 単体 swiftc でも tsc でも出ず、xcodebuild でだけ落ちる。Codex に xcodebuild を回させない指示だと「完了」と報告してくるので、この層は自分で xcodebuild して緑まで持っていく。annotation の要否は当て推量でなく警告差分で決める。

### 6. 生成テストの定型バグ (TS/一般)

- **export 名に自信が無いと `(m as any).foo ?? (m as any).bar` とハズレ名でヘッジする / 存在しない export を dead branch で参照する** → vitest は緑、`tsc --noEmit` だけ赤。タスクが要求していなくても必ず `tsc --noEmit` を通す。修正はヘッジ/dead branch の除去 (実装は触らない)。
- **日付・時刻 assert が絶対時刻ベタ書き・「安全な正午」に寄る** → `TZ=UTC` で 1 回掃引し、危険窓 (境界時刻) の標本は自分で足す。TZ シフト変異はシフト窓に標本が無いと原理的に検出できない。
- **合成データの剰余条件 (`i%5` で上書き等) を Codex 自身が忘れた assert を書く** → 偽 fail はまず fixture の seed 式から期待値を再計算する。
- **「欠落で throw」テストに既存の成功 fixture を流用する** → 非 Optional 追加と衝突するので inline JSON に差し替えさせる。
- **型が禁じる入力 (必須キー欠落) でバグを「検出」する過剰仕様** → type-valid な入力で再現するか probe してから帰属する。
- **mock を 0 引数 impl で書き `mock.calls` が `[]` タプルに推論される (TS2493)** → モックは本物のシグネチャで宣言させる。

### 7. 指示解釈の癖

- **「可能な範囲でテスト移植」を「移植ゼロ + 理由書き」に倒す / 「不変」契約の資産の文言を勝手に簡略化する** → テスト移植は配置先・ハーネス・skip 条件まで指定した専用ラウンドに分け、「不変」資産は完了後に旧実装と文言レベルで diff 突合。
- **禁止事項は名指しされた 1 箇所しか守らない** (例: MapView の角丸クリップ禁止を守りつつ、同ラウンド新規の CameraView に同じ形を書く) → 禁止はパターンとして横展開し、触ったファイルを grep で確認。
- **コメントを英語で書く・repo の注釈規約から外れる・oxfmt に落ちる整形を出す** → 実装が正しくてもコメントは自分で書き直し、整形を当て直してからテスト/型/lint をもう一度回す。
- **偽 fail ラウンドを減らす渡し方**: 実装を読ませずに済むシグネチャだけ渡す — `go doc` / `.d.ts` (`tsc --emitDeclarationOnly`) / swiftmodule strings / 稼働 API の probe で採った wire shape。「assert は設計から・シグネチャ確認だけ許可・ロジックは読むな」と明示する。

## Why

Codex CLI は安全寄り既定 (read-only sandbox / network 遮断) と、非対話モードでの「それらしい体裁で正常終了する」失敗モードを併せ持つ。exit code・報告文・自己申告のどれも成果物の実在を保証しないため、検証は常にファイルシステムと git の実体に対して行う必要がある。

## 関連

- [[tool-quirk/codex-cli-imagegen-tool]] — codex CLI の imagegen ツールの癖 (別ファイルで存続)
