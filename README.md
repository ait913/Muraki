# Muraki

AI 主体で開発を進めるためのオーケストレーション workspace。Claude Code を Leader、Codex/Gemini を団員として動かす自律開発チームの「事務局」を担う。実装は配下の各プロジェクト (独立 git repo) が持ち、ここはチームの規約・知見・記録だけを管理する。

## 思想

- **Leader が設計を書かない**: 意図理解 → 召集 → 統合判断に専念。設計は Architect、実装は Developer、テストは Reviewer に分離
- **設計 → 実装 → テストを役割で分離**: Architect が「実装で迷う余地のない」設計doc を書き、Developer は doc から実装し、Reviewer は **コードを見ず** doc だけからテストを生成する
- **ナレッジを残す**: 失敗・パターン・ツールの癖を `knowledge/` に蓄積。次セッション以降が grep で引ける
- **ライブで書き換える**: 規約・仕様が変わったら**追記でなく置換**。矛盾の蓄積を防ぐ

## ロール

| ロール | 担当 | 役目 |
|---|---|---|
| **Leader** | Claude Code | 意図理解 → 団員召集 → 統合判断 |
| **Researcher** | `researcher` subagent (Gemini 優先、Codex 併用) | 設計**前**のリサーチ |
| **Architect** | `architect` subagent | 設計doc 執筆 (UI/UX 含む) |
| **Developer** | `developer` subagent (Codex) | 設計doc から実装 |
| **Reviewer** | `reviewer` subagent (Codex) | 設計doc から**テスト生成** → 走らせる |

詳細: [`CLAUDE.md`](./CLAUDE.md)

## ディレクトリ構成

```
Muraki/
├── CLAUDE.md                       # 組織規約 (Claude Code が auto-load)
├── README.md                       # この本
├── .claude/settings.local.json     # codex apply / gemini --yolo を deny
├── knowledge/                      # クロスプロジェクト知見
│   ├── INDEX.md                    # 自動生成
│   ├── library/                    # ライブラリ・API知見
│   ├── pattern/                    # 設計パターン
│   ├── gotcha/                     # ハマりどころ
│   └── tool-quirk/                 # Codex/Gemini の癖
├── projects/                       # AI 管理プロジェクト本体 (各々独立 git repo)
│   ├── _TEMPLATE.md                # 新規 PJ の CLAUDE.md 雛形
│   ├── _pre/                       # 初期リサーチアーカイブ
│   └── <slug>/                     # 各 PJ (= 別 GitHub repo へ submodule なし)
├── sessions/                       # セッションごとの作業記録
│   ├── _TEMPLATE.md                # 雛形
│   └── <yyyy-mm-dd>-<short-id>.md
├── scripts/                        # メタ運用スクリプト
│   └── gen-knowledge-index.py
└── worktrees/                      # 並列作業用 git worktree (gitignore)
```

## 記録の場所と責務

書く前に**どこに置くか**判断する。4 層あり責務は被らせない。

| 層 | パス | 読まれ方 | 書く対象 |
|---|---|---|---|
| **memory** | `~/.claude/projects/.../memory/` | 全セッション auto-load | Touri 本人 / 働き方 / 進行中状況 / 外部参照 |
| **knowledge** | `Muraki/knowledge/`, `<project>/.knowledge/` | grep on-demand | 技術事実 / 設計パターン / ハマり所 / ツール癖 |
| **設計doc** | `<project>/.designs/<YYYYMMDD>-<feature>.md` | 該当作業時のみ | その機能の設計 (Architect 専任) |
| **session report** | `Muraki/sessions/<yyyy-mm-dd>-<short-id>.md` | 必要時 grep | 作業記録 / 課題点 / いい点 / 追加ナレッジ |

詳細は [`CLAUDE.md`](./CLAUDE.md) の「記録の場所と責務」「session report」「プロジェクトごとの CLAUDE.md」。

## 並列実行 (GitHub Flow + worktree)

複数機能 / 複数 Claude セッションが並列で動く前提。1 機能 = 1 ブランチ = 1 worktree。

```sh
git -C Muraki/projects/<project> worktree add ../../worktrees/<project>-<slug> -b feature/<slug>
# ... 作業 ...
git -C Muraki/projects/<project> worktree remove ../../worktrees/<project>-<slug>
git -C Muraki/projects/<project> branch -d feature/<slug>
```

## ナレッジに目を通す

新規調査・新規設計の前に既存知見を引く:

```sh
grep -ril "<keyword>" Muraki/knowledge/ Muraki/projects/<slug>/.knowledge/ 2>/dev/null
cat Muraki/knowledge/INDEX.md
```

INDEX 再生成: `python3 Muraki/scripts/gen-knowledge-index.py`

## ライセンス

未定。AI 開発スタイルの参照用途で公開している。
