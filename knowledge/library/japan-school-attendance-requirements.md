---
title: 日本の大学・専門学校の出席要件 — 設置基準は規定なし・慣行は「授業回数の2/3」(以上か超えるかで1回ずれる)
category: library
project: global
tags: [attendance, university, vocational-school, regulation, japan, education]
created: 2026-10-29
sources:
  - https://laws.e-gov.go.jp/api/2/law_data/331M50000080028
  - https://laws.e-gov.go.jp/api/2/law_data/351M50000080002
  - https://laws.e-gov.go.jp/api/2/law_data/501M60000080006
  - https://www.kindai.ac.jp/international-studies/files/research-and-education/curriculum/outline/syllabus_alart.pdf
  - https://tokaigakuin-u.ac.jp/wp-content/themes/daigaku/pdf/public_info/rishu_tebiki_h26/123_26dai3.pdf
  - https://okayamatakebe.isu.ac.jp/media/files/disclosure/2023_new/SotsuNintei.pdf
  - https://www.ujc.ac.jp/absence/files/absence.pdf
  - https://www.titech.ac.jp/guide/guide_2026/graduate/pdf/12-16.pdf
model-era: opus-4.8
---

## Context
出席管理アプリ (atender) で「大学は率でなく回数で決まるのか」を確かめるために、法令と実在学校の学則/便覧の原文を取得して確認した (2026-10-29)。法令は e-Gov API v2 (`https://laws.e-gov.go.jp/api/2/law_data/<law_id>?law_full_text_format=json`) の全文を取得して文字列検索した。

## What
- **大学設置基準 (331M50000080028, 2026-09-04 施行版) と専修学校設置基準 (351M50000080002) の全文に「出席」「欠席」は 0 回**。大学設置基準第21条は単位=45時間学修を標準、授業時間は「おおむね十五時間から四十五時間までの範囲で大学が定める」とだけ規定。→ 出席要件は各学校の学則・履修規程・シラバス依存。
- 実在学校の原文は**大学も専門学校も基準は「率」**: 近畿大学国際学部「授業回数の 3 分の 2 **を超える**出席がなければ受験資格を失う」、東海学院大学「70%以上」、岡山・建部医療福祉専門学校「3 分の 2 以上」+「欠席が 3 分の 1 を超えると原則卒業不可」、函館厚生院看護専門学校「3 分の 2 以上」。回数表現は同志社法科大学院「15 回で 5 回以上欠席なら単位不可」(検索スニペットのみ・原文未確認) 1 件だけ。
- **「以上」か「超える」かで 15 回授業の許容欠席が 5 回/4 回に割れる** (2/3 以上=10 回出席、2/3 超=11 回出席)。
- 遅刻換算: 宇都宮短大「30 分未満の遅刻・早退 3 回=欠席 1 回、30 分以上は欠席」。公欠は「欠席に数えない」(東京科学大) と「欠席扱いだが受験資格・評価で不利にしない」(宇都宮短大) の 2 流儀。
- 大学では科目ごとに別基準がありうる (近畿大「授業担当教員から異なる指示がある場合を除いて」「出欠の取り決めはシラバスに記載」)。
- **率が法令に出てくるのは別の制度**: 大学等における修学の支援に関する法律施行規則 (501M60000080006、修学支援新制度、大学・短大・高専・専門学校) の別表で「出席率が六割以下」(廃止)・「八割以下」(警告)。専門学校の学則が 80% を採る根拠かは未確認。

## Why
設置基準は「学修量」(単位) を縛るだけで、出席は教育課程の運用として各校に委ねられているため。「回数で語られる」のは 2/3 率を授業回数で割った運用上の翻訳。

## How to apply
- 「大学=回数、専門=率」と決め打ちしない。入力モデルは「率 or 回数上限」を選べ、境界 (以上/超える)・遅刻換算・公欠の扱いを学校ごとに持てる形が実態に近い。
- 閾値を全科目共通の 1 値にすると、科目ごとに基準が違う大学を表現できない。
- IT/デザイン系専門学校の出席率 (80/90%) の学則原文は取れていない — 必要なら対象校の学則 PDF を直接取得して確認すること。
- 出典 PDF の取得は WebFetch が PDF を読めない (圧縮ストリームで本文空) ので、`curl -sL -A "Mozilla/5.0"` で落として `pdftotext -layout` を使う。日本語ファイル名の URL は curl が HTML を返すことがある (`file` で PDF か確認)。
