---
title: App Store Guideline 1.2 (UGC) の現行原文 — 「24 時間」「EULA」は旧版の孫引き
category: library
project: global
tags: [app-store, app-review, guideline-1.2, ugc, report, block]
created: 2026-09-17
sources: [https://developer.apple.com/app-store/review/guidelines/ (2026-09-17 WebFetch 直接確認), sessions/2026-09-16-d33aab8e]
---

## Context

Bloom. の初回審査で Guideline 2.1 Information Needed が来て、録画に「UGC の通報・ブロック機構」を含めろと要求された。要件の原文を確認したときの記録。

## What

現行の 1.2 原文 (2026-09-17):

> Apps with user-generated content or social networking services must include:
> - A method for filtering objectionable material from being posted to the app
> - A mechanism to report offensive content and timely responses to concerns
> - The ability to block abusive users from the service
> - Published contact information so users can easily reach you

- **「通報から 24 時間以内に削除」「EULA に明記」は現行原文に存在しない**。SEO 記事 (BuddyBoss 等) が旧版 (2017 年以前の詳細列挙版) の文言を引き続けているだけ。安全側の目安に使うのは無害だが、固定要件として設計に書かない
- 「人間のレビューキューが必須か、記録 + 受理で足りるか」は原文に無い。小規模 (運営 1 人) では「DB 記録 + 運営が確認できる経路 + 閾値で自動非表示」で解釈するのが現実的
- 招待制の非公開グループでも 1.2 が免除されるという公式根拠は無い (forums/thread/96314 は回答ゼロ)。審査メールが明示的に録画に含めろと言ってきた実績あり

## How to apply

- UGC を持つアプリは提出前に 4 点 (投稿前フィルタ / 通報 + 対応 / ブロック / 連絡先) を揃える。初回提出で削られると新規 build + 実機録画のやり直しになる (Bloom で実際に発生)
- 「ブロック」の意味はアプリのモデルに合わせて定義する (Bloom は対等メンバーなので双方向不可視、追放ではない)
