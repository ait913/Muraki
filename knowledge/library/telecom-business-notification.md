---
title: 電気通信事業の届出 (回線非設置・アプリ内チャット) の書き方
category: library
tags: [電気通信事業法, 届出, e-Gov, チャット, DM, コメント, 法務]
created: 2026-10-26
project: global
sources:
  - https://www.soumu.go.jp/menu_seisaku/ictseisaku/denkitsushin_suishin/tetsuzuki/kokunaihoujin.html
  - https://www.soumu.go.jp/main_content/001005312.pdf
  - https://www.soumu.go.jp/main_content/000793019.pdf
  - https://www.keidanren.or.jp/journal/times/2022/0407_10.html
  - https://zenn.dev/nodatakumi/articles/a5d069ace48602
  - https://shinsei.e-gov.go.jp/recept/procedure/lists/procedureInformation?gtaTetCd=145181GA00001
---

## Context
Bloom (グループ内コメント・チャット) の届出内容を決めた時に総務省の様式原本を読んで得た (sessions/2026-10-26-f079ad57)。

## What
- 特定の利用者間だけのメッセージ (DM・閉じたグループのチャット・メンバー限定コメント) は「他人の通信の媒介」で届出対象。公開 SNS の投稿は対象外。
- 書類は 3 点: **様式第8** 届出書 / **様式第3** ネットワーク構成図 / **様式第4** 提供する電気通信役務。
- 様式第4: 「31 インターネット関連サービス (IP電話を除く。)」に `○（クローズドチャット）`。機能を増やしてもクローズドチャットの範囲なら書類は同じ。
- 様式第3: 【提供するサービス】クローズドチャット、届出者 ⇄ インターネット ⇄ 利用者A/B、使用するサーバーとその**設置者**。
- 様式第8 (回線非設置): 3(1) 提供区域 = 全国。3(2)〜(4)・4 (設備の概要)・5 は記入不要。事業開始予定年月日は要記入 (事前届出が原則)。
- **e-Gov の個人の届出画面には様式第3 が出てこないが必要**。様式第3 の見出しに「第9条第1項第1号関係」= 届出書の添付書類。PDF にして添付する。個人は住民票の写しを総合通信局へ別送 (関東の事例)。
- WebFetch は総務省 PDF を読めない (圧縮ストリーム)。保存されたバイナリを Read で開けば読める。

## Why
届出の様式は回線設置事業者向けの欄が大半で、アプリ事業者が書くのは区分の ○ と構成図程度。画面に出る欄だけ見ると添付書類を落とす。

## How to apply
チャット・DM 系の機能を設計する PJ は、リリース前に上の 3 点を揃える。添付欄の場所など画面の細部は未確認なので、迷ったら提出先の総合通信局に電話で聞く。
