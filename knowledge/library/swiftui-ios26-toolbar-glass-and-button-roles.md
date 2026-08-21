---
title: iOS 26 の toolbar item glass 除去 (sharedBackgroundVisibility) と ButtonRole.close / back の実態
category: library
tags: [swiftui, ios26, liquid-glass, toolbar, buttonrole, availability, apple]
project: global
created: 2026-07-30
sources:
  - "SDK 実測: iPhoneSimulator26.5.sdk SwiftUI.swiftinterface L5570-5584 / L9100-9109 / L21712-21715"
  - "実機ランタイム実測: iPhone 16 iOS 26.5 / iOS 18.2 Simulator (2026-07-30)"
  - https://developer.apple.com/tutorials/data/documentation/swiftui/toolbarcontent/sharedbackgroundvisibility(_:).json
  - https://developer.apple.com/tutorials/data/documentation/swiftui/buttonrole/close.json
model-era: opus-4.8
---

## Context

atender の toolbar に `ToolbarItem(placement: .topBarLeading) { Menu {...} label: { HStack { Text; chevron } } }`
を置くと、iOS 26 では自動でカプセル状の glass 背景が付く (実機 FB「ボタンじゃなくてテキストだけにしたい」)。
併せて sheet の close / back を Apple 標準部品で出す手段を確定させた。

## What

### 1. toolbar item の自動 glass を消すのは `sharedBackgroundVisibility(.hidden)` — 唯一効く手段

```swift
ToolbarItem(placement: .topBarLeading) { menuLabel }
    .sharedBackgroundVisibility(.hidden)     // ← ToolbarItem に付ける。中身の View ではない
```

- シグネチャ (swiftinterface 逐語):
  `extension ToolbarContent { func sharedBackgroundVisibility(_ visibility: SwiftUICore.Visibility) -> some ToolbarContent }`
  同名で `CustomizableToolbarContent` 版もある。**引数は専用型ではなく素の `Visibility`** (`.automatic` / `.visible` / `.hidden`)
- `@available(iOS 26.0, macOS 26.0, *)` / tvOS・watchOS・visionOS unavailable
- **`ToolbarContent` の extension なので、`ToolbarItem` / `ToolbarItemGroup` 自体に付ける。**
  ラベル側 View に付けようとしても型が合わない
- 公式説明: 「隣接 item は同一の logical grouping で glass 背景を共有する。hidden にすると
  その item は自分だけの grouping に置かれる」 (docs 逐語)

**ランタイム実測 (iPhone 16 / iOS 26.5)**:

| 手段 | 結果 |
|---|---|
| 素の `ToolbarItem { Menu }` | 白いカプセル glass 背景が付く |
| `+ .sharedBackgroundVisibility(.hidden)` | **カプセル消滅。素のテキスト + chevron になる (狙い通り)** |
| `Menu.buttonStyle(.plain)` を中身に付ける | **完全に無効。素のときと screenshot が byte 一致 (md5 同一)** |
| `ToolbarItem(placement: .principal)` | カプセルは付かない (= これも有効な逃げ道)。ただし**中央寄せ**になる |

- `.toolbarBackground(_:)` / `.toolbarBackgroundVisibility(_:for:)` は**バー全体の背景**の API で、item のカプセルとは無関係
- `.buttonStyle(.plain)` が効かないのは、カプセルが Button の style ではなく
  **toolbar 側が item を包む共有背景**として描かれているため

### 2. iOS 17/18 側は何もしなくてよい (else 節は素の ToolbarItem)

iOS 18.2 で「素の ToolbarItem」と「`#available(iOS 26)` ガード付き版」を撮って
ナビバー領域を pixel diff した結果 **差分 0 / 90000 px**。iOS 25 以下にそもそも glass カプセルは無い。

★ ただし**文字色が OS で違う**: iOS 26 は label 色 (黒)、iOS 18 は accent (青) で描かれる。
色を揃えたいなら `.foregroundStyle` / `.tint` を明示すること。

### 3. `ButtonRole.close` は実在。ただし「円形 xmark」になるのは toolbar の中だけ

- `ButtonRole` の全メンバー (SDK 26.5 逐語): `.destructive` / `.cancel` (iOS 15.0+)、
  **`.confirm` / `.close` は iOS 26.0+**
- ラベル省略イニシャライザは実在:
  `@available(iOS 26.0, *) extension Button where Label == DefaultButtonLabel { init(role: ButtonRole, action: ...) }`
  → `Button(role: .close) {}` が書ける (`DefaultButtonLabel` も iOS 26.0+ の公開型)

**ランタイム実測 (iOS 26.5) — 見た目は文脈依存**:

| 置き場所 | 描画 |
|---|---|
| 通常の VStack 内、`Button(role: .close) {}` | **青い文字「Close」** (円形 xmark ではない) |
| `+ .buttonStyle(.glass)` | glass カプセル + 文字「Close」 |
| `+ .buttonStyle(.glassProminent)` | 青い塗りカプセル + 文字「Close」 |
| **`ToolbarItem` の中** | **円形 glass の ✕ アイコン** (期待する形) |

→ 「円形 ✕」が欲しければ **toolbar item として置く**。本文中に置くと文字ボタンになる。
docs の discussion も「The following view would display a close button **in the toolbar**」と書いており、
toolbar 前提の role。

### 4. `ButtonRole` に back は存在しない。sheet 内の戻るは NavigationStack のシステム back

- `Button(role: .back)` は `error: type 'ButtonRole' has no member 'back'` (コンパイル実証)
- SwiftUI に back button を生成する公開 API は無い (`navigationBarBackButtonHidden` = 隠す側だけ)
- ★ **sheet 内 `NavigationStack` で push すると、`.navigationTitle` を付けなくても
  システムの円形 glass back button (chevron.left) だけが出る** (iOS 26.5 実測)。
  タイトル無しの詳細画面で「戻るだけ」を標準部品で出せる

## Why

iOS 26 の toolbar は「隣接 item をまとめて 1 枚の glass に載せる」モデルに変わった。
だから消し方も item 単位の grouping 制御 (`sharedBackgroundVisibility`) であって、
Button の style や bar の background では触れない。
`ButtonRole` も「意味を宣言して描画は文脈に委ねる」設計なので、同じ `.close` が
本文では文字、toolbar では円形 ✕ になる。**role の見た目を docs から推測してはいけない**。

## How to apply

- 「toolbar item を素のテキストにしたい」→ `ToolbarItem { ... }.sharedBackgroundVisibility(.hidden)` を
  `if #available(iOS 26.0, *)` で分岐。else は素の `ToolbarItem`。
  `@ToolbarContentBuilder` の computed property に切り出すと `switch` + `#available` が両立する
  (iOS 17.0 target で typecheck 実証済)
- 「close/back を標準部品で」→ close は **toolbar item に** `Button(role: .close) {}`、
  back は **sheet 内 NavigationStack の push** に任せる (自前 chevron を描かない)
- role の見た目を仕様に書く前に、置く文脈 (toolbar / 本文 / alert) を含めて 1 回撮る

## 5. `.principal` に大きいタイトルを置くときの実寸 (iPhone 16 / 393pt 幅で実測 2026-07-30)

`ToolbarItem(placement: .principal)` に `Text(...).font(.title2.weight(.bold))` (24pt bold) を置き、
leading にシステム back (sheet 内 NavigationStack の push)、trailing に `Button(role: .close)` がある状態。

### 使える幅
| OS | 上限幅 (GeometryReader 実測) |
|---|---|
| iOS 26.5 | **247 pt** |
| iOS 18.2 | **277 pt** |

iOS 26 の方が 30pt 狭い (両端の円形 glass ボタンが幅を食う)。
`カレンダーを取り込む` (10文字) = 206pt は**両 OS で等倍・切れずに収まる**。

### modifier の効き (16文字 "ルームのカレンダーを取り込む設定" で比較)
| modifier | 実測幅 | グリフ高 | 結果 |
|---|---|---|---|
| 無し | 244 | 19.3 (等倍) | 切れる |
| `lineLimit(1)` + `minimumScaleFactor(0.75)` | 247 | 14.3 | **切れる** (0.75 が下限で足りない) |
| **`lineLimit(1)` + `minimumScaleFactor(0.5)`** | 247 | 14.3 | **全文表示**。19文字でも 11.3pt に縮んで全文入る |
| `layoutPriority(1)` | 245 | 14.3 | **無効** (付けないのと同じ) |
| **`fixedSize()`** | **329** | 19.3 | ★**back/close の下に潜り込んで重なる。使用禁止** |

→ 採用形は **`.lineLimit(1).minimumScaleFactor(0.5)`**。
`minimumScaleFactor` は iOS 18/26 とも効く (グリフ実寸が縮む)。効かないのは `layoutPriority`。

### その他
- `.principal` に **glass カプセルは付かない** → `sharedBackgroundVisibility(.hidden)` は不要 (付けても pixel 同一)
- **`.navigationTitle` を併記しても `.principal` が勝つ** (navigationTitle の文字列は一切描画されない)
- iOS 26 の `ToolbarItem(placement: .title)` は `.principal` と**見た目・実測幅とも同一**
- ★ **`topBarLeading` に同じ 24pt bold Text を置くと iOS 26 では幅 31pt しか貰えず「カ…」に潰れる**
  (glass カプセルに閉じ込められる)。長いタイトルを leading に置く実装は iOS 26 で破綻する
- iOS 18 の back button は前画面タイトルを文字で出す (`< root`) が、タイトルが長いと自動で chevron のみに縮む
