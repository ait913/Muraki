---
title: 片方のクライアントを正典にして別クライアントを揃えるときは、純粋関数と単体テストの表を写す
category: pattern
project: atender
tags: [parity, port, ios, web, pure-function, test-table, design-doc, reviewer]
created: 2026-10-30
sources:
  - Muraki/projects/atender/.designs/20261030-web-parity-with-ios.md (§2 / §6 / §7.L / §8.2)
---

## Context

atender で「Web を iOS と全く同じ仕様に」と言われた。iOS は build 18〜21 で学期の引継ぎ・終了提案・公開時間割の取込・科目別の出席基準を足しており、Web は 5 タブ時代のまま。Developer (Codex) と Reviewer は iOS の Swift を読まない前提で、設計 doc 1 本で揃える必要があった。

## What

1. **ロジックは「純粋関数を同名ファイルで写す」単位で移植する**。iOS の `enum X { static func … }` (SemesterRollover / TemplateImportLogic / TimetablePublishLogic / TemplateSuggestionLogic / CourseRuleLogic / RoomTimetableLogic / TodayTimeline / ClassTransferLogic …) を `apps/web/src/lib/X.ts` に同じ関数名で置く。画面側はそれを呼ぶだけにする
2. **正典クライアントの単体テスト (XCTest) を、入力 → 出力の表として doc に転記する**。Reviewer はその表をそのまま Vitest にでき、正典と写しの drift が表で検出できる。iOS 側のテストに Reviewer の註 (「設計の例示ミス、規範を採る」等) があれば、規範側の値で書く
3. **プラットフォームの暗黙の意味論を規則として書き出す**。写すと黙って変わるもの:
   - 月の加算: Foundation の `date(byAdding: .month)` は月末で頭打ち (8/31 + 6 か月 = 2/28)。JS の `setMonth` は繰り上がる (3/3)
   - 「今日」: iOS は `SchoolClock` で JST 固定。Web で `new Date()` / dayjs をそのまま使うと端末 TZ になる
   - Swift の `split` は空要素を捨てる。JS の `split` は残す
   - Swift の `String <` と JS の `<` は ASCII の id なら一致する (それ以外は要注意)
   - 永続化キーは正典と同名にする (`UserDefaults` のキー → `localStorage` のキー)
4. **ブリーフ (調査報告) の「正典はこう動く」は正典のコードで確かめる**。今回 3 件ずれていた: 招待リンクは「自動参加しない」→ 実際は `.task` で 1 回自動参加 / 学期管理の新規追加は「提案値あり」→ 実際は空 / 学期削除の 409 toast → iOS は `.http(409)` しか捕まえておらず JSON body 付きの 409 (`.api`) で別の文言に落ちていた (= 正典側のバグ)。正典のバグは写さず、意図どおりに実装して正典側を報告に上げる
5. **時刻で発火する新機能 (「全学期が終わっていたら提案」) を足すときは、既存テストの既定 fixture の日付を数える**。MSW 既定の学期が `2026-09-30` 終了で、実日付 (2026-10-30) では全ルートテストに提案ダイアログが出る状態だった。既定 fixture を遠い未来に寄せ、発火を見るテストだけが過去の学期を使う

## Why

- 画面単位で「iOS のこの画面と同じに」と書くと、Developer は iOS を読みに行くか推測する。純粋関数の境界で切ると、doc が型と表だけで完結し、Developer と Reviewer が独立に同じ値に到達できる
- 正典の XCTest は「正典が満たしている挙動」の実測値なので、新しく表を発明するより確実で、正典の変更時にも突き合わせる対象が 1 つで済む
- 写しで壊れるのは書かれた規則でなく、プラットフォームが暗黙に与えていた規則 (暦・TZ・split)。ここだけは doc に明文化しないと Reviewer も気付けない

## How to apply

- 「A を B と同じに」の設計では、最初に正典側の `enum`/`struct` の純粋関数と、その単体テストのファイルを列挙する。doc の構成は「純粋関数のシグネチャ (写し先の言語)」→「入出力表 (正典のテストの転記 + 危険窓の標本)」→「画面の挙動 (関数を呼ぶ箇所と文言)」の順にする
- 日付・文字列操作を写すときは、上の 3. の表をチェックリストとして全部当てる。規則から出る値 (月末 + 6 か月等) は scratchpad で実走してから表に書く
- 調査報告に「正典は〜する」とあったら、そのファイルの該当行を開いて確かめ、ずれていたら doc の「現状の実測」節に補正として残す
- 時刻・日付で出る UI を足す前に `grep -rn "endDate\|startDate" tests/msw` で既定 fixture の日付を確認する
