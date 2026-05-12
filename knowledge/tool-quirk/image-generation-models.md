---
title: 画像生成は Codex (Images2 / gpt-image-1) 優先、Gemini Nanobanana より高品質
category: tool-quirk
project: global
tags: [image-generation, codex, gemini, model-selection, logo]
created: 2026-05-10
sources:
  - ユーザー直接判断 (2026-05-10)
---

## Context

CLAUDE.md の役割分担では「Gemini = 画像などビジュアル面」と一般原則が書かれている。しかし画像生成タスクに限って言えば、ユーザーの実体験に基づく判断として **Codex (内部的に OpenAI Images-2 / gpt-image-1) の方が出力品質が高い**。Gemini系の Nanobanana (旧Imagen) より優位。

## What

- ロゴ・アイキャッチ・LP用画像・アプリアセット など **画像生成系タスクは Codex に振る**
- Gemini は **画像認識・OCR・マルチモーダル理解 (PDF読み取り含む)** の方は引き続き優秀なので、こちらは Gemini 維持
- つまり「画像 → Gemini」じゃなく、「画像生成 → Codex / 画像理解 → Gemini」と細分する

## Why

- Codex/OpenAIの Images-2 (gpt-image-1) はテキストレンダリング・構図の正確さ・スタイル指示への忠実度が現時点で業界トップ水準
- Gemini Nanobanana は速度・コスト面では優位だが、ロゴのような「正確な文字+繊細な構図」が必要な場面では品質が劣る
- Murakiプロジェクトのアプリは救命系で、ロゴは信頼感を出す必要がある → 品質優先

## How to apply

- ロゴ生成・アプリアイコン・キービジュアルは Codex で生成依頼
- PDF読み取り・画像内容認識・マルチモーダル理解は Gemini で
- CLAUDE.md の「Gemini = ビジュアル面」は「ビジュアル**理解**」と読み替える
- 画像生成のプロンプトは英語で詳細に書く (Images-2は英語プロンプトが安定)
- 1回で決まらない前提で、3-5案を並列生成してから選定

## 例外・注意

- 大量生成 (50枚以上一気に) でコスト気になる場合は Gemini も検討の余地
- 写真風 (実写) は SD系/Midjourney も視野に入るが、ロゴ・イラスト系は Codex 優位
