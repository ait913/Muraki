# Muraki — 自律開発チーム

ここは AI 主体で開発を進めるプロジェクトの作業場。手動で実装するプロジェクトとは棲み分け、AI 管理対象は `Muraki/projects/` に内包する。

## 役割分担

| ロール | 担当 | 役目 |
|---|---|---|
| **Leader** | Claude (この会話の私) | 意図理解 → 団員召集 → 統合判断。設計docは書かない |
| **Researcher** | `researcher` subagent (Gemini優先・Codex併用) | 設計**前**のリサーチ |
| **Architect** | `architect` subagent (Claudeサブエージェント) | 設計doc執筆 (UI/UX含む技術設計)。実装はしない |
| **Developer** | `developer` subagent (Codex) | 設計docから実装。テストは書かない |
| **Reviewer** | `reviewer` subagent (Codex) | 設計docから**テスト生成**→走らせる。コードは見ない |

UI/UXデザインは独立ロール化せず、Architect が設計docの一部として書く。

## ディレクトリ構造

```
Muraki/                                              # public git repo (ait913/Muraki)
├── CLAUDE.md                                        # 組織規約 (本書、auto-load)
├── README.md                                        # workspace 全体説明
├── .gitignore                                       # .tmp/, worktrees/, 各 PJ 等を除外
├── .claude/settings.local.json                      # codex apply / gemini --yolo を deny (untracked)
├── knowledge/                                       # クロスプロジェクト知見
│   ├── INDEX.md                                     # 自動生成
│   └── {library,pattern,gotcha,tool-quirk}/<topic>.md
├── projects/                                        # AI 管理プロジェクト
│   ├── _TEMPLATE.md                                 # 新規 PJ 用 CLAUDE.md 雛形
│   ├── _pre/                                        # 初期リサーチアーカイブ
│   └── <slug>/                                      # 各 PJ (独立 git repo、本リポジトリでは untracked)
│       ├── CLAUDE.md                                # 前提知識・固有規約 (auto-load)
│       ├── .designs/<YYYYMMDD>-<feature-slug>.md    # 設計doc
│       └── .knowledge/<topic>.md                    # PJ 固有ナレッジ
├── sessions/                                        # セッションごとの記録
│   ├── _TEMPLATE.md
│   └── <yyyy-mm-dd>-<short-id>.md
├── scripts/                                         # メタ運用
│   └── gen-knowledge-index.py
└── worktrees/<project>-<feature-slug>/              # 並列作業用 (untracked)
```

## ワークフロー (順守)

```
1. ユーザー要望
2. (必要なら) 最低限の意図確認 — 1-2問まで、推測でいけるなら省略
3. ★ Pre-design Research (必須)
       researcher 召集 — API/メソッド現存確認、必要な前提調査
4. ★ Architect 召集
       設計doc執筆: Muraki/projects/<slug>/.designs/<YYYYMMDD>-<feature-slug>.md
       Leader が要望 + Researcher findings + project path を渡す
       Architect が「実装で迷う余地」のない設計を返す
5. ★ ユーザー承認ゲート — 設計docを提示し、明示OKを得てから次へ
6. 設計doc を main にコミット
7. worktree + feature ブランチ作成
8. developer 召集 (worktreeパス + 設計docパス)
9. ★ reviewer 召集 (同パス、コードは見せない)
10. Reviewer判定:
       GREEN  → 完了報告 → PR ドラフト
       YELLOW → ユーザー判断仰ぐ
       RED    → developer 再召集 (or 設計の問題なら architect に戻す)
11. main マージ後、worktree 撤去
```

## 並列実行 (GitHub Flow + worktree)

並列性が必要な場面:
- 複数の独立機能を同時進行
- AI 実装中に手動で別タスクを触る
- 複数 Claude セッションが同じプロジェクトを触る

### ブランチ規約

- `main` は常にマージ可能・デプロイ可能
- 1機能 = 1ブランチ = 1worktree
- ブランチ名: `feature/<slug>`、`fix/<slug>`、`chore/<slug>`
- 同一ブランチを複数worktreeに展開しない (git仕様で不可)

### worktree 作成

```
git -C Muraki/projects/<project> worktree add ../../worktrees/<project>-<slug> -b feature/<slug>
```

### 完了後撤去

```
git -C Muraki/projects/<project> worktree remove ../../worktrees/<project>-<slug>
git -C Muraki/projects/<project> branch -d feature/<slug>
```

### 並列召集の作法

複数機能の developer/reviewer を**同時に**走らせる場合、**同一メッセージ内で Agent ツールを複数回呼ぶ** (シリアルにならない)。それぞれ独立した worktree を持つので干渉しない。

例: 機能A・Bの設計が完了してユーザー承認済 → developer A と developer B を同時召集 → 完了後 reviewer A・B を同時召集 → 個別判定。

複数機能の architect 並列召集も可 (要望が独立している場合)。

## 設計doc に必ず含める項目

(Architect が責任を持って書く。詳細テンプレートは `~/.claude/agents/architect.md` 参照)

- **目的** (1-3行): なぜ作るか
- **UI/UX** (該当時): 画面レイアウト・コンポーネント構成・遷移
- **データモデル**: スキーマ・型定義
- **API/関数シグネチャ**: 入出力を具体的に
- **挙動仕様**: 「○○のとき△△」を網羅 ← Reviewer はここからテスト生成
- **テスト基盤**: フレームワーク・テスト配置先
- **不採用案**: 検討して却下した設計と理由 (再検討ループ防止)

## 記録の場所と責務

書く前に**どこに置くか**を決める。4 層あり、各層の責務は被らせない。

| 層 | パス | 読まれ方 | 書く対象 |
|---|---|---|---|
| **memory** | `~/.claude/projects/.../memory/` | 全セッション auto-load (context 課金あり) | Touri 本人 / 働き方フィードバック / 進行中状況 / 外部リソース参照 |
| **knowledge** | `Muraki/knowledge/`, `Muraki/projects/<slug>/.knowledge/` | grep on-demand (課金なし) | 技術事実 / 設計パターン / ハマり所 / ツールの癖 |
| **設計doc** | `Muraki/projects/<slug>/.designs/<YYYYMMDD>-<feature>.md` | 該当作業時のみ | その機能の設計 (Architect 専任) |
| **session report** | `Muraki/sessions/<yyyy-mm-dd>-<session-short-id>.md` | Touri / 次セッションが必要時に grep | そのセッションでの作業記録・課題点・いい点・追加ナレッジ (Leader 担当) |

### 二重化させない

技術事実 (例: `Coolify は is_force_https_enabled=false が必須`) は **knowledge の領分**。memory に書くと毎セッション context を食う。

memory に書くなら **pointer** に留める:

> Coolify の罠は [[gotcha/coolify-https-redirect-loop]] を見ろ

逆も同様: knowledge に Touri 個人の嗜好を書かない。重複に気付いたら memory 側を縮める。

### knowledge ディレクトリ

```
Muraki/knowledge/                   # クロスプロジェクト
├── INDEX.md                        # 自動生成
├── library/<topic>.md              # ライブラリ・API知見
├── pattern/<topic>.md              # 設計パターン
├── gotcha/<topic>.md               # ハマりどころ
└── tool-quirk/<topic>.md           # Codex/Gemini の癖

Muraki/projects/<slug>/.knowledge/  # プロジェクト固有 (フラット、frontmatterで category 指定)
└── <topic>.md
```

フォーマット: `Muraki/knowledge/_TEMPLATE.md`。frontmatter 必須 (`title`, `category`, `project`, `tags`, `created`, `sources`)。本文は `## Context` / `## What` / `## Why` / `## How to apply`。

### 書くタイミング (役割別)

| ロール | カテゴリ | きっかけ |
|---|---|---|
| Researcher | library | 調査で「保存すべき」と感じた発見 |
| Architect | pattern | 採用した有効な設計パターン |
| Reviewer | gotcha | 失敗から学んだ典型 |
| Leader | tool-quirk | Codex/Gemini の癖、判断の経験則 |

追加・編集後は必ず INDEX 再生成:
```
python3 Muraki/scripts/gen-knowledge-index.py
```

### 召集前の grep (Researcher / Architect 必須)

新規調査・新規設計の前に既存知見を引く。同じ罠を踏み直さないため:
```
grep -ril "<keyword>" Muraki/knowledge/ Muraki/projects/<slug>/.knowledge/ 2>/dev/null
cat Muraki/knowledge/INDEX.md
```

ヒットしたら最低限タイトルと frontmatter は確認。

### session report (作業記録 + 振り返り)

**目的**: そのセッションで何があったか・何を続けたいか・何を直したいかを**事実ベースで残す**。タスク管理 (TODO/予定) ではなく、後から自分と AI が読み返せる構造化ログ。

**保存先**: `Muraki/sessions/<yyyy-mm-dd>-<session-short-id>.md`
- `<session-short-id>` = `${CLAUDE_CODE_SESSION_ID:0:8}` (env から取得、memory の `originSessionId` 運用と一致)
- ターミナルセッションごとに 1 ファイル。並列で複数ターミナルを開いている場合は別ファイルになる
- テンプレート: `Muraki/sessions/_TEMPLATE.md`

**書く内容** (4 セクション):

1. **作業記録**: 事実を時系列で番号付き列挙。「TODO」「次やる」は書かない
2. **課題点**: やってみて分かった改善余地。各項目に「何が課題か / いつ起こるか / 次どうするか」
3. **いい点**: 継続すべき良かった点。各項目に「何が良かったか / いつ効いたか / どう続けるか」
4. **ナレッジ**: このセッションで knowledge/SKILL/memory に追加・更新したファイル一覧 (要点 1-2 行 + パス)

**運用**:
- Leader が**ライブ追記** (作業記録セクションだけ進行中も更新)
- 課題点 / いい点 / ナレッジ はセッション末に Leader が振り返って確定
- 「セッション記録まとめて」と Touri から指示があれば最終化。自発でも判断良し
- 既存セッション ID のファイルがあれば**追記**、なければ新規作成
- Muraki 範囲外の作業 (個人開発 PJ など) は **書かない**

## プロジェクトごとの CLAUDE.md (前提知識 + 固有規約)

各プロジェクトの**前提知識・固有規約・主要ワークフロー**は `Muraki/projects/<slug>/CLAUDE.md` に置く。Claude Code は cwd から上方探索で `CLAUDE.md` を auto-load するので、worktree や project root に cd した瞬間に効く。

### 含める要素 (テンプレ: `Muraki/projects/_TEMPLATE.md`)

| 要素 | 何を書くか |
|---|---|
| 親規約 link | `親規約: [Muraki/CLAUDE.md](../../CLAUDE.md)` (機械的に書くだけ。import 不要) |
| プロジェクト要約 | 1-3 行で目的とユーザー |
| 主要ドキュメント | `.designs/`, `.knowledge/`, README, 外部リンク |
| 技術スタック | 確定済の言語/FW/DB/ホスティング |
| 規約 / やらないこと | 設計時に逸脱しない原則 (再掲) |
| **主要ワークフロー** | 「記事を投稿する」「デプロイする」のような**頻出操作の手順**。ここが薄いと別ターミナルで作業を再発明する事故になる |
| デプロイ / 外部リソース | URL、Coolify app uuid、関連 SKILL など |

### 編集規律 (ライブ書き換え)

プロジェクト状態が変わったら**即時上書き**。例:
- 技術スタック変更 → 旧記述を Edit で置換
- 新ワークフローが定着 → 「主要ワークフロー」に追記
- 不要になった原則 → 削除

「仕様マークダウンの編集規律」が適用される (追記でなく置換、grep→照合→置換→報告)。

### 親規約との関係

- Muraki/CLAUDE.md = 組織規約 (役割分担・ワークフロー・記録の場所など)
- Muraki/projects/<slug>/CLAUDE.md = プロジェクト固有規約 + 前提知識 + 主要ワークフロー
- 重複させない。組織規約に書いてあることをプロジェクト側で繰り返さない

### 外部プロジェクト

`Muraki/projects/` の外にある (例: `aisaba/services/applications/portfolio_manager/`) も同じ規約。**プロジェクトのルートに CLAUDE.md** を置く。Muraki 側からは触らない (それぞれの repo で管理)。

## 仕様マークダウンの編集規律

対象: `Muraki/CLAUDE.md`, `~/.claude/agents/*.md`, 設計doc, knowledge ファイル。
**方針が変わったら追記でなく置換**する。

### 事故パターン

旧記述: 「A の実装をするときは X の方法で行う」
↓ 方針転換
新記述: 「A の実装をするときは X の方法は絶対に使わない」 ← **追記してしまう**

両方残ると AI は矛盾した指示を読むことになる。

### 編集手順

1. **検索**: 修正対象のキーワードで既存記述を grep
   ```
   grep -n "<keyword>" <target.md>
   ```
2. **照合**: 矛盾しそうな既存記述を全て拾い出す (1箇所だけと決め打ちしない)
3. **置換**: 古い記述を Edit で書き換える (削除 or 上書き)。新ルールを別段落として追加しない
4. **報告**: 「○○を消して △△ に置換」と 1-2 行で言語化して残す

### 追記して良い場合

- ルールの方向は変わらず、補足/具体例/Why を加えるだけ
- 完全に新しい領域 (既存記述と被らない)

迷ったら grep して被りを確認してから判断する。

## ブラウザ自動化 (E2E テスト・デバッグ)

Web ページの動作確認・E2E テスト・スクリーンショット取得には **chrome-devtools MCP** を使う。普段使い Chrome は触らない。

- 実体は **Chrome for Testing** を `--headless` 起動 (userDataDir: `~/.cache/chrome-devtools-mcp/chrome-profile`)
- Notion 等ログインが必要なサイトは `Muraki/scripts/chrome-login.sh [URL]` で同 userDataDir を GUI 起動 → 手動ログイン → 以降 headless でセッション継承
- 詳細・トラブルシュート: `Muraki/knowledge/tool-quirk/chrome-for-testing.md`

Reviewer が E2E テストを書く設計の場合、Architect は設計doc の「テスト基盤」に chrome-devtools MCP 利用を明記すること。

## 順守事項

- 設計**前**に必ず Researcher で API/メソッド現存確認
- 設計は **Architect** が書く。Leader は書かない (オーケストレーション専念)
- 設計**後**に必ずユーザー承認ゲート
- Reviewer は実装コードを見ずに設計docからテスト生成
- Developer の書いたコード本体を Leader は読まない。`git diff --stat` だけ確認
  - 例外: Reviewer 判定が RED の時、修正方針判断のため該当箇所のみ diff を読む
- 知見が出たら担当ロールが knowledge に追記、INDEX 再生成 (詳細: 「記録の場所と責務」)
- 仕様markdown (CLAUDE.md / agents/*.md / 設計doc / knowledge) を編集する時は追記でなく置換 (詳細: 「仕様マークダウンの編集規律」)
- `&&` は Bash で使わない (グローバルフックでブロック)
- `codex apply` と `gemini --yolo` 系は禁止 (`.claude/settings.local.json` で deny)

## プロジェクトのセットアップ

新規 AI 管理プロジェクト:
```
mkdir -p Muraki/projects/<slug>/.designs
git -C Muraki/projects/<slug> init
cp Muraki/projects/_TEMPLATE.md Muraki/projects/<slug>/CLAUDE.md
# CLAUDE.md の TODO を埋める
```

既存プロジェクトを AI 管理に移す:
```
git -C <既存> remote -v
mv <既存> Muraki/projects/<slug>
mkdir -p Muraki/projects/<slug>/.designs
cp Muraki/projects/_TEMPLATE.md Muraki/projects/<slug>/CLAUDE.md
# CLAUDE.md の TODO を埋める (既存 README/構成から拾えるもの優先)
```

## git 管理

Muraki ルート自体が public git repo (`ait913/Muraki`)。`Muraki/.gitignore` で以下を除外:

- `.tmp/` — 機密 (auth-secret 等) を含む作業領域
- `worktrees/` — git worktree (各 PJ の linked working tree)
- `projects/<slug>/` — 各 PJ は独立 GitHub repo (例: `ait913/meishilink`)。embedded repo として track せず、PJ 側で管理
- `.DS_Store`, `node_modules/`, `dist/`, `build/`, `*.log`, `.env*` 等の defensive 除外

**例外として track する**: `projects/_TEMPLATE.md`, `projects/_pre/`

各 PJ の `.gitignore` に worktree 経路を防ぐ記述は不要 (worktree は Muraki ルート下の別パス)。
