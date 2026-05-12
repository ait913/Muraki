---
title: "vCard 日本語名刺生成 (vCard 3.0 + 振り仮名)"
category: library
project: global
tags: [vcard, vcf, japanese, ios, android, contacts]
created: 2026-05-08
sources:
  - https://datatracker.ietf.org/doc/html/rfc6350
  - https://www.npmjs.com/package/vcard-creator
  - https://www.npmjs.com/package/vcard4
---

## Context
日本向け Web 名刺アプリで、iOS/Android 連絡先に取り込める .vcf を Node で生成する。

## What
- **採用**: `vcard-creator` (active, 2026 更新あり、ESM/TS、依存ゼロ)。
- **却下**: `vcards-js` (2019 で停止)、`node-vcard` (放棄)。
- **vCard バージョン**: **3.0 を採用**。4.0 は iOS18/Android16 でも互換が不安定。
  3.0 は文字化け事例が圧倒的に少ない。
- **N フィールド**: `N:山田;太郎;;;` (Family;Given;Middle;Prefix;Suffix)。
  `FN:山田 太郎` (表示用) も併記。
- **振り仮名**: `X-PHONETIC-LAST-NAME:やまだ` / `X-PHONETIC-FIRST-NAME:たろう` を入れると
  iOS/Android の連絡先で正しくソートされる (RFC 9554 の `PHONETIC` パラメータは
  4.0 用なので 3.0 では X- フィールドのまま)。
- **CHARSET=UTF-8**: 3.0 では deprecated だが Android レガシー対策として書く例もある。
  モダンライブラリ任せで省略推奨 (UTF-8 without BOM が前提)。

## Why
- 日本語姓名を分割しないと iOS で「太郎」が family に入って五十音順が壊れる。
- 振り仮名を入れないと連絡先一覧で「やまだ」セクションに出ない。

## How to apply
```ts
import VCard from "vcard-creator";
const v = new VCard("3.0");
v.addName("山田", "太郎"); // last, first
v.addCompany("株式会社XX");
v.addPhoneNumber("090-xxxx-xxxx", "CELL");
v.addEmail("a@b.jp");
// 振り仮名は raw 行で
v.addRawLine("X-PHONETIC-LAST-NAME:やまだ");
v.addRawLine("X-PHONETIC-FIRST-NAME:たろう");
const vcf = v.toString();
```
出力は **UTF-8 without BOM** で `Content-Type: text/vcard; charset=utf-8` で返す。
