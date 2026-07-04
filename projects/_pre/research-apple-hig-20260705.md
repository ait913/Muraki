# Apple HIG 精読 — UI設計用の具体数値と観点 (2026-07-05)

調査経路: developer.apple.com の HIG は SPA で WebFetch では本文が取れないため、
docs JSON エンドポイント (`https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<slug>.json`)
を直叩きしてパースした (一次ソース)。全数値は 2026-07-05 時点の HIG 本文からの転記。

対象読者: Architect (Web + SwiftUI iOS 両方のデザイン観点集の材料)。

---

## 0. 前提: 2025-2026 の HIG は「Liquid Glass」世代

- 2025-06 以降、HIG 全体が Liquid Glass (コントロール層が content の上に浮くガラス材質) 前提に書き換わっている。tab bar / toolbar / sidebar は「content と同一平面ではなく上に浮く」レイヤーとして扱う。コンテンツは画面端・コントロール下まで伸ばす (background extension / scroll edge effect)。
  — https://developer.apple.com/design/human-interface-guidelines/layout
- 旧 HIG の「Navigation (hierarchy / flat / content-driven の3構造)」ページは現行 HIG に存在しない (JSON endpoint 404 で確認)。現行はコンポーネント別 (tab-bars / sidebars / toolbars) に分散。3構造論を設計docに書くなら「旧 HIG 由来の分類」と明記すること。
- navigation-bars の URL は現在「Toolbars」ページに統合されている (2025-06-09 の change log: "incorporated navigation bar guidance")。
  — https://developer.apple.com/design/human-interface-guidelines/navigation-bars

---

## 1. Typography

出典: https://developer.apple.com/design/human-interface-guidelines/typography

### 書体の使い分け
- SF (San Francisco) ファミリー = sans serif。変種: SF Pro, SF Compact, SF Arabic/Armenian/Georgian/Hebrew, SF Mono。丸みのある UI に合わせる Rounded 変種あり。
- New York (NY) = serif。単独でも SF との併用でも成立するよう設計されている。
- システムフォント: iOS/iPadOS/macOS/tvOS/visionOS = **SF Pro**、watchOS = **SF Compact** (コンプリケーションは SF Compact Rounded)。
- SF/NY は variable font で **dynamic optical sizing** (Text/Display の離散オプティカルサイズは統合済み。実行時はシステムが自動補間するので「20pt で Text→Display 切替」という旧ルールを手動適用する必要はない。デザインツールが variable font 非対応の場合のみ離散オプティカルサイズを使う)。
- トラッキングはサイズごとにシステムが自動調整。モックアップ用の tracking 表が HIG にある (SF Pro: 12pt=0, 17pt=-26/1000em, 20pt=-23/1000em 等)。

### デフォルト / 最小フォントサイズ (custom font にも適用)
| Platform | Default | Minimum |
|---|---|---|
| iOS, iPadOS | 17 pt | 11 pt |
| macOS | 13 pt | 10 pt |
| tvOS | 29 pt | 23 pt |
| visionOS | 17 pt | 12 pt |
| watchOS | 16 pt | 12 pt |

(accessibility ページにも同表: https://developer.apple.com/design/human-interface-guidelines/accessibility)

### iOS/iPadOS Dynamic Type — Large (default) の text style 表
| Style | Weight | Size (pt) | Leading (pt) | Emphasized |
|---|---|---|---|---|
| Large Title | Regular | 34 | 41 | Bold |
| Title 1 | Regular | 28 | 34 | Bold |
| Title 2 | Regular | 22 | 28 | Bold |
| Title 3 | Regular | 20 | 25 | Semibold |
| Headline | Semibold | 17 | 22 | Semibold |
| Body | Regular | 17 | 22 | Semibold |
| Callout | Regular | 16 | 21 | Semibold |
| Subhead | Regular | 15 | 20 | Semibold |
| Footnote | Regular | 13 | 18 | Semibold |
| Caption 1 | Regular | 12 | 16 | Semibold |
| Caption 2 | Regular | 11 | 13 | Semibold |

- xSmall〜xxxLarge の7段 + AX1〜AX5 の5段が仕様化されている (AX5 で Body 53pt まで)。Emphasized weight 列は 2025-12-16 に追加された新しい仕様。
- macOS の text style は別表 (Body 13pt/16、Large Title 26pt/32 等)。**macOS は Dynamic Type 非対応**。

### 運用ルール (HIG 明文)
- Light/Ultralight/Thin weight は避ける (特に小サイズ)。Regular/Medium/Semibold/Bold を使う。
- built-in text styles を優先 (Dynamic Type + accessibility サイズが自動で効く)。
- 3行以上のテキストに tight leading を使わない。
- テキストサイズ拡大時: 重要コンテンツ優先で拡大 (全要素を一律拡大しない)、アイコンも連動拡大 (SF Symbols なら自動)、truncation 最小化、大サイズでは stacked layout / カラム数削減を検討。
- accessibility: テキストは最低 200% まで拡大可能に (watchOS は 140%)。

### 日本語の注意
- **HIG は日本語 (Hiragino 等) の個別数値を明文化していない**。HIG 上の言及は「SF Symbols に Japanese を含む script 変種がある」「システムフォントは extensive range of languages をサポート」のみ。日本語 UI での行間・字詰め調整値は HIG 出典では出せない (不確定事項)。

---

## 2. Layout / Spacing

出典: https://developer.apple.com/design/human-interface-guidelines/layout

- **8pt グリッドは HIG に存在しない**。HIG が明文化するのは「system-defined safe areas, margins, and guides を尊重せよ」まで。標準マージンの具体 pt 値も HIG 本文には無い (layout guide / 公式デザインテンプレート Figma/Sketch に委譲)。8px グリッドは業界慣習であって HIG 出典ではない — 設計docで「HIG準拠」と書かないこと。
- Safe area = 「toolbar, tab bar その他のビューに覆われない領域」。Dynamic Island・カメラハウジング回避に必須。
- **タッチターゲットの正確な記述** (buttons ページ): "As a general rule, a button needs a hit region of **at least 44x44 pt** — in visionOS, 60x60 pt — to ensure that people can select it easily."
  — https://developer.apple.com/design/human-interface-guidelines/buttons
- accessibility ページのコントロールサイズ表 (default / minimum):
  | Platform | Default | Minimum |
  |---|---|---|
  | iOS, iPadOS | 44x44 pt | 28x28 pt |
  | macOS | 28x28 pt | 20x20 pt |
  | tvOS | 66x66 pt | 56x56 pt |
  | visionOS | 60x60 pt | 28x28 pt |
  | watchOS | 44x44 pt | 28x28 pt |
- **要素間 padding の唯一の明文数値** (accessibility): 「bezel のある要素の周囲 **約12pt**、bezel のない要素の可視端の周囲 **約24pt**」。
  — https://developer.apple.com/design/human-interface-guidelines/accessibility
- iOS: **full-width ボタンを避ける** (システムマージン内に inset する。full-width にするなら筐体の角 R と safe area に調和させる)。
- iPadOS: ウィンドウ自由リサイズ前提。「compact への切替をできるだけ遅らせる」「1/2, 1/3, 1/4 分割サイズでテスト」。
- macOS: ウィンドウ下端に重要コントロールを置かない (下端が画面外に出がち)。
- tvOS: safe area = 上下 60pt・左右 80pt inset。グリッド仕様表あり (horizontal spacing 40pt 等)。
- 読み順 (top→bottom, leading→trailing) で重要度配置。RTL 考慮。
- デバイス寸法表あり (iPhone 17 Pro: 402x874pt @3x 等) — 必要時に原典参照。

---

## 3. Color / Dark Mode

出典: https://developer.apple.com/design/human-interface-guidelines/color , https://developer.apple.com/design/human-interface-guidelines/dark-mode , https://developer.apple.com/design/human-interface-guidelines/accessibility

### Semantic colors (iOS/iPadOS)
- 背景2系統×3階層:
  - plain view: `systemBackground` / `secondarySystemBackground` / `tertiarySystemBackground`
  - grouped table: `systemGroupedBackground` / `secondarySystemGroupedBackground` / `tertiarySystemGroupedBackground`
  - Primary=view 全体、Secondary=view 内のグループ化、Tertiary=secondary 内のグループ化。
- 前景: `label` / `secondaryLabel` / `tertiaryLabel` / `quaternaryLabel` / `placeholderText` / `separator` / `opaqueSeparator` / `link`。
- **semantic の意味を転用しない** (separator を文字色に使う等は禁止)。**色値のハードコード禁止** (リリースごとに変動しうる)。
- systemGray〜systemGray6 の6段 (SwiftUI に相当するのは gray のみ)。

### コントラスト要件 (WCAG AA 準拠、Accessibility Inspector の判定基準)
| Text size | Weight | 最小コントラスト比 |
|---|---|---|
| 〜17pt | All | **4.5:1** |
| 18pt〜 | All | 3:1 |
| All | Bold | 3:1 |
- Dark Mode ページ: 最低 4.5:1、**カスタム前景/背景色は 7:1 を目標** (特に小テキスト)。

### Dark Mode
- **アプリ内独自の appearance 設定を作らない** (システム設定に従う)。
- Dark palette は light の単純反転ではない。
- iOS Dark Mode は背景が **base / elevated** の2セット (sheet・popover・multitasking で elevated が自動適用)。カスタム背景色はこの奥行き表現を壊す。
- 白背景の画像は Dark 文脈で「光る」ので少し暗くする。
- ラベルは system label colors、テキスト描画は system views を使う。

### Accent / Liquid Glass の色
- Liquid Glass は無色がデフォルト。色を付けるのは強調に値する要素 (primary action, status) だけ。**prominent ボタンは記号/文字でなく背景に accent color を適用**。複数コントロールの背景に色を付けない。
- カラフルな背景を持つアプリでは toolbar/tab bar は monochromatic を推奨。単色基調のアプリならブランド色を accent に。
- 色だけで情報を伝えない (shape/icon/text を併用)。文化圏での色の意味差に注意。

---

## 4. コンポーネント別

### Buttons — https://developer.apple.com/design/human-interface-guidelines/buttons
- hit region ≥ 44x44pt (visionOS 60x60pt)。周囲に十分な空間。
- **prominent スタイルは 1 view に 1〜2 個まで**。優先choice の区別は「サイズでなくスタイル」で。
- Role: Normal / Primary (accent color、Return キー応答) / Cancel / Destructive (system red)。**破壊的アクションに primary role を与えない**。
- カスタムボタンには必ず press state。
- 非即時完了アクションはボタン内 activity indicator + ラベル変更 ("Checkout"→"Checking out…")。

### Lists & tables — https://developer.apple.com/design/human-interface-guidelines/lists-and-tables
- テキスト中心データは list/table、サイズがばらつく・画像大量なら collection。
- 行テキストは簡潔に。ナビゲーション階層は選択行を永続ハイライト、選択リストはチェックマーク。
- info button (detail disclosure) はナビゲーションに使わない — drill-down は disclosure indicator。
- iOS grouped スタイル = header/footer + 余白でグループ分離。

### Sheets / Modality — https://developer.apple.com/design/human-interface-guidelines/sheets , /modality
- modal を使うのは「明確な利益がある時だけ」。モーダルタスクは simple/short/streamlined。
- **modal 内に階層を作らない** ("app within your app" 化禁止)。subview が要るなら単一パスに。
- **sheet は同時に1枚だけ**。sheet から sheet を出すなら先に閉じる。alert のみ最上位に重ねられるが、alert も同時1枚。
- detent: large (全高) と medium (約半分)。custom detent 可。resizable sheet には grabber を付ける。swipe-to-dismiss をサポートし、未保存変更があれば action sheet で確認。
- ボタン配置 (iOS/iPadOS): **Cancel = top toolbar の leading、Done = trailing**。Done を置くなら必ず Cancel か Back とペア。Cancel+Done+Back の3つ同時は避ける。
- 複雑・長時間のフローには sheet でなく full-screen modal (動画・写真編集など) や別 window (iPad/macOS)。
- 時限自動 dismiss の UI を最小化 (accessibility/cognitive)。

### Toolbars (旧 navigation bars 統合) — https://developer.apple.com/design/human-interface-guidelines/navigation-bars
- 3配置: leading edge (back/sidebar toggle/title、カスタマイズ不可) / center (カスタマイズ可・溢れたら自動 overflow) / trailing edge (常時可視、primary action・search・More)。
- タイトルは **15字以内**。アプリ名をタイトルにしない。
- グループは**最大3つ**を目安。text ラベル付きアクション同士は fixed space で分離。
- **`.prominent` スタイルの primary action は1つだけ、trailing 側**に (Done/Submit)。
- 標準 Back/Close ボタンを使う (テキスト "Back"/"Close" にしない)。
- iOS: **large title** はスクロールで standard title に遷移し現在地を伝える。
- 背景・tint のカスタムは減らす (Liquid Glass + scroll edge effect に委ねる)。

### Tab bars — https://developer.apple.com/design/human-interface-guidelines/tab-bars
- **navigation 専用。アクションを置かない** (アクションは toolbar)。
- **タブ数の明示上限は現行 HIG に無い**。「fewer tabs の方が navigate しやすい」「overflow (More tab) を避けよ」が現行表現。iPad のカスタマイズ可能タブは「デフォルト5個以下を目安」と明文 (compact/regular 間の連続性のため)。
- タブを隠さない・disable しない (空なら理由を表示)。modal 表示中だけは tab bar が隠れてよい。
- ラベルは単語1つを推奨。アイコンは **filled variant** がプラットフォーム標準 (iOS tab bar は fill を自動選択)。
- iOS: 画面下に浮く (Liquid Glass)。スクロールで最小化可、accessory (MiniPlayer 等) 統合可、trailing に専用 search tab 可。
- iPadOS: tab bar は画面上部。**sidebar と相互変換可能な convertible tab bar** (`sidebarAdaptable`) が推奨パターン。

### Sidebars — https://developer.apple.com/design/human-interface-guidelines/sidebars
- **まず tab bar を検討** (コンテンツに空間を譲れる)。セクションが多い複雑アプリだけ sidebar。
- **階層は2レベルまで**。それ以上は split view (sidebar + content list + detail)。
- デフォルトで隠さない。ユーザーによるカスタマイズ・表示切替を許す。

### SF Symbols — https://developer.apple.com/design/human-interface-guidelines/sf-symbols
- **9 weight が SF フォントの weight と1:1対応** — 隣接テキストと weight を厳密一致させられる。
- **3 scale (small / medium=default / large)** — テキストの cap height 基準。point size を変えずに強調を調整。
- rendering modes: monochrome / hierarchical / palette / multicolor (+SF Symbols 7 で gradient)。variable color は「変化」の表現専用 (深度表現には hierarchical)。
- variant 使い分け: **outline = toolbar・リスト等テキスト併記の場所 / fill = iOS tab bar・swipe action・選択状態**。多くの view は自動選択。
- アプリアイコン・ロゴへの使用は規約で禁止。

---

## 5. Navigation / IA

- 現行 HIG に「hierarchy / flat / content-driven」の3構造ページは**存在しない** (旧 iOS HIG の記述。現行では tab-bars / sidebars / toolbars / modality に分散)。
- 現行の IA 指針の実体:
  - タブ = アプリのセクション分割 (状態保持つき切替)。少ないほど良い。overflow するなら構造を見直す。
  - 複雑な構造 = sidebar か convertible tab bar (iPad)。sidebar 内階層は2レベルまで、深いなら split view。
  - 階層内の前進後退 = toolbar (navigation bar) の Back。大見出し (large title) で現在地提示。
  - 一時的タスク = modal (sheet)。modal 内に階層を作らない・多重 modal 禁止が実質の「深さ制限」。
- iPhone は片手持ち前提: 「画面の中央〜下部が到達しやすい」「list row の swipe・back swipe を必ず活かす」 — https://developer.apple.com/design/human-interface-guidelines/designing-for-ios

---

## 6. Web アプリに転用する時の注意 (Researcher 見解)

- pt は iOS の論理単位。Web では概ね 1pt→1px (CSS px) 読み替えで慣習通用するが、これは HIG の明文ではない。
- HIG のコントラスト表は WCAG AA そのものなので Web にそのまま適用可 (4.5:1 / 18pt≒24px 以上は 3:1)。
- 44x44pt はタッチ Web でも 44x44px として使える (WCAG 2.5.8 の最小 24px より厳しい、Apple 基準)。
- Dynamic Type の代替は rem ベース + ユーザーのブラウザ文字サイズ尊重。
