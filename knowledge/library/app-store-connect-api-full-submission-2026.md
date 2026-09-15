---
title: App Store Connect API v1 だけで新規アプリを審査提出する (2026-09時点、Web UI 必須の2箇所を含む)
category: library
tags: [apple, app-store-connect, ios, submission, age-rating, privacy]
created: 2026-09-16
project: global
sources:
  - https://developer.apple.com/documentation/appstoreconnectapi
  - https://developer.apple.com/documentation/appstoreconnectapi/ageratingdeclarationupdaterequest/data-data.dictionary/attributes-data.dictionary
  - https://developer.apple.com/documentation/appstoreconnectapi/screenshotdisplaytype
  - https://blakecrosley.com/blog/app-store-social-media-declaration-september-2026
  - https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/
---

## Context
iOS アプリ (バージョン 1.0, PREPARE_FOR_SUBMISSION, TestFlight ビルド有) を **Web UI を極力使わず JWT (Admin key) + App Store Connect API v1 だけ**で審査提出する設計の事前調査。ASC API の resource 名は SPA docs の JSON エンドポイント (`library/apple-developer-docs-json-endpoint.md`) を直叩きして 2026-09-16 時点の実仕様を確認した。

## What
API で完結する項目 (endpoint 確認済、body 形は Apple 公式 docs JSON から実測):

| 項目 | endpoint | 備考 |
|---|---|---|
| バージョンローカライズ (description/keywords/whatsNew等) | `PATCH /v1/appStoreVersionLocalizations/{id}` | 属性: description, keywords, locale, marketingUrl, promotionalText, supportUrl, whatsNew |
| appInfo ローカライズ (name/subtitle/privacy URL) | `PATCH /v1/appInfoLocalizations/{id}` | 属性: locale, name, privacyPolicyText, privacyPolicyUrl, subtitle, privacyChoicesUrl |
| カテゴリ | `PATCH /v1/appInfos/{id}` relationships.primaryCategory/secondaryCategory | id 例: `SOCIAL_NETWORKING` (search由来、**実 GET /v1/appCategories で最終確認すること**) |
| 年齢レーティング | `PATCH /v1/ageRatingDeclarations/{id}` | 2026-07時点で 28〜29属性。**2026-09から `socialMedia`/`socialMediaAgeRestricted` (boolean) が全アプリ必須** (下記★) |
| 価格 (無料化) | `POST /v1/appPriceSchedules` | relationships: app, baseTerritory, manualPrices → 各 manualPrice は relationships.appPricePoint (customerPrice="0.00" のものを `GET /v1/apps/{id}/appPricePoints?filter[territory]=...` から検索)。**"free" 専用 endpoint は無い。実 GET 1回で customerPrice=0.00 の price point id を確認してから実装すること** (公式の動作例は見つからず、二次情報のみ) |
| 配信国 (全世界) | `POST /v2/appAvailabilities` | attributes.availableInNewTerritories=true, relationships.territoryAvailabilities (各territory available=true) |
| Content Rights | `PATCH /v1/apps/{id}` attributes.contentRightsDeclaration | 値: `DOES_NOT_USE_THIRD_PARTY_CONTENT` / `USES_THIRD_PARTY_CONTENT` |
| スクショ | `POST /v1/appScreenshotSets` (screenshotDisplayType) → reserve/upload/commit | ★ **6.9インチ用の enum は無い。`APP_IPHONE_67` を流用する** (fastlane deliver が実際にこのマッピングで運用中)。ドキュメント上も `screenshotDisplayType` の列挙値は APP_IPHONE_67 が最大で、67/69専用の新規値は追加されていない (2026-09時点、developer forum でも未解消の既知ギャップ)。2026年は最大サイズ (6.9"iPhone / 13"iPad) だけ用意すれば小さい方は自動生成される |
| ビルド紐付け | `PATCH /v1/appStoreVersions/{id}` relationships.build | endpoint 実在確認済 (200) |
| レビュー詳細 | `POST/PATCH /v1/appStoreReviewDetails` | 属性: contactEmail, contactFirstName, contactLastName, contactPhone, demoAccountName, demoAccountPassword, demoAccountRequired, notes |
| 審査提出 | `POST /v1/reviewSubmissions` (attributes.platform="IOS", relationships.app) → `POST /v1/reviewSubmissionItems` (relationships.reviewSubmission + appStoreVersion) → `PATCH /v1/reviewSubmissions/{id}` attributes.submitted=true | 旧 `appStoreVersionSubmissions` は DELETE のみ残存 = 実質廃止、reviewSubmissions が現行 |

★ **設計に影響する重大発見**:

1. **App Privacy (「栄養成分表示」データ収集開示) は API に存在しない。** ASC API の topicSections を全走査したが privacy/data usage 系リソースは無い。**Web UI (App Information > App Privacy) での入力が必須**で、未入力だと新規アプリ提出がブロックされる。「Web UI を使わない」設計の前提が崩れる唯一の必須ブロッカー。
2. **EU DSA trader status も API 非対応。** アカウントレベルの設定で、EU配信の有無・無料/有料を問わず全開発者アカウントに要求される (2025-02-17〜)。ASC API に該当 endpoint は無く、Web UI 手動設定のみ。ただし**アカウント単位の一度きりの設定**なので、既存アカウントで設定済みなら新規アプリ提出のたびには不要。
3. **2026-09〜 年齢レーティングに `socialMedia`/`socialMediaAgeRestricted` (boolean) が全アプリ必須。** 「友達間で位置情報を共有」「投稿のフィード」等がある場合、Appleの定義 (「UGCをソーシャルフィード等で再配信・増幅・インタラクトできる」) に触れると `socialMedia=true` 扱いとなり、13+ 未満は強制的に不可 (Time Allowances 上もSocial Mediaカテゴリ扱い)。13歳未満を許可したいならDeclared Age Range API連携+完全ブロックの3条件を満たして `socialMediaAgeRestricted` で緩和が必要。位置共有SNS系の設計では必ずこの分岐を明示すること。
4. 年齢レーティングのコンテンツ記述子は基本 `NONE` / `INFREQUENT_OR_MILD` / `FREQUENT_OR_INTENSE` の3値 (二次情報+定義文で確認、公式 JSON docs は型を単に `string` としか書いておらず enum一覧は非公開)。

## Why
「Web UI を極力使わない」という設計前提に対し、**App Privacy と Trader Status の2つは Apple側が意図的に API を提供していない** (プライバシー表示は虚偽申告防止のため対話的UIに固定している可能性が高い、trader statusは法的本人確認絡み)。ここを見落とすと「全部API化したのに提出直前でUIに戻る」事故になる。

## How to apply
- 設計docに「App Privacy と Trader Status(初回のみ) は Web UI 必須」と明記し、自動化フローの外に出す
- 年齢レーティングの `socialMedia` 系は機能仕様 (フィード・拡散性の有無) を先に確定してから値を決める。決め方をArchitectに投げず、プロダクト判断としてLeaderがTouriに一言確認する価値あり (エスカレーション「プロダクト判断」に該当しうる)
- スクリーンショット・価格point・カテゴリidは、本番実行前に GET 1回で値を実測確認してから PATCH/POST を打つ (二次情報だけで確定しない)
