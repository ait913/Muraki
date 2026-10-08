---
title: ASC 輸出コンプライアンス (暗号化申告) を API で扱う — 2026-10 実仕様 (標準アルゴリズム OSS 利用アプリ)
category: library
project: global
tags: [apple, app-store-connect, export-compliance, encryption, testflight, libsodium]
created: 2026-10-08
sources:
  - https://developer.apple.com/documentation/appstoreconnectapi/app-encryption-declarations.md
  - https://developer.apple.com/tutorials/data/documentation/appstoreconnectapi/appencryptiondeclaration/attributes-data.dictionary.json
  - https://developer.apple.com/tutorials/data/documentation/appstoreconnectapi/appencryptiondeclarationcreaterequest/data-data.dictionary/attributes-data.dictionary.json
  - https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-builds-_id_-relationships-appencryptiondeclaration
  - https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations.md
  - https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption
  - https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation
  - https://developer.apple.com/forums/thread/849352
---

## Context
Flutter 等で libsodium (XChaCha20-Poly1305) など標準アルゴリズムの OSS 実装を同梱したアプリを TestFlight / 審査に出すとき、Web UI を使わず ASC API v1 で輸出コンプライアンスを済ませたい。Apple docs JSON + `.md` 直取り (`library/apple-developer-docs-json-endpoint.md`、`developer.apple.com/documentation/...<slug>.md` も本文が取れる) で確認。

## What
- **Apple の判定表** (help/reference/export-compliance-documentation-for-encryption): OS 内蔵暗号のみ = 書類不要 / **業界標準アルゴリズムを OS 外で使う = French encryption declaration のみ必要 (フランスで配信する場合だけ)** / 独自アルゴリズム = CCATS + French declaration。
- ASC の質問フロー (標準アルゴ・非独自・フランス非配信) の結論文言は「書類のアップロードは不要。Info.plist で暗号を使わない旨を指定すれば毎回の質問を省略できる」(forum thread 849352 の質問者引用、二次。ASC 画面の一次スクショ未確認)。
- 同スレッドの罠: `ITSAppUsesNonExemptEncryption=YES` で `ITSEncryptionExportComplianceCode` 空のままアップロードすると **エラー 90592** (Invalid Export Compliance Code)。YES は「書類承認済みで code を持っている」場合のみ素直に通る。
- **ビルド側 (build 単位)**: `Build.attributes.usesNonExemptEncryption` (bool)。`PATCH /v1/builds/{id}` で `usesNonExemptEncryption` と `relationships.appEncryptionDeclaration` を設定可 (API 3.0 で追加)。`PATCH /v1/builds/{id}/relationships/appEncryptionDeclaration` (body `{"data":{"type":"appEncryptionDeclarations","id":"…"}}`, 204) もある。
- ★ 旧 `POST /v1/appEncryptionDeclarations/{id}/relationships/builds` は availability が「1.0.0 - 2.4.0」止まり (事実上廃止、3.0 で上記に置換)。使わない。
- 宣言 (declaration) : build = 1 : N (宣言は app 単位で再利用、build は 1 宣言)。TestFlight 外部ベータ審査前に `usesNonExemptEncryption=true` のビルドは宣言リンク必須 (公式 note)。
- **`POST /v1/appEncryptionDeclarations`** (API 3.6 追加): attributes 必須 4 つ = `appDescription`(string) / `availableOnFrenchStore` / `containsProprietaryCryptography` / `containsThirdPartyCryptography` (bool)。relationships.app は必須だが 3.6 で「deprecated」表記 (unavailable ではない)。`usesEncryption` / `exempt` / `platform` は **作成 body に無い** (read 側 attributes のみ)。応答 201。
- read 側: `appEncryptionDeclarationState` ∈ CREATED / IN_REVIEW / APPROVED / REJECTED / INVALID / EXPIRED、`codeValue` (= plist の `ITSEncryptionExportComplianceCode`)、`documentName/Type/Url`、`uploadedDate`。
- 書類: `POST /v1/appEncryptionDeclarationDocuments` (fileName, fileSize, relationship declaration) → アップロード操作 → `PATCH …/{id}` で commit。審査目安は公式「約 2 営業日」、forum 逸話は「数ヶ月」。
- Apple 公式 (Security docs): YES を入れるのは「OS 内蔵/免除形態を超えて暗号を使う」場合。免除形態でも米 BIS 年次 self-classification report が別途必要になりうる (Apple が Important で注記、書類を Apple に出す場合は不要)。法的判断はデベロッパ責任。

## Why
暗号化申告は UI 前提と思われがちだが、declaration 作成・ビルド紐付け・ビルド属性更新はすべて API にある。ただし「標準アルゴリズム + 非フランス」なら declaration 自体が不要で、`usesNonExemptEncryption=false` を build に PATCH / plist に入れるだけで済む、というのが ASC 自身の案内。

## How to apply
- 最短: plist に `ITSAppUsesNonExemptEncryption=false` (ASC 案内どおり) → 既に MISSING_COMPLIANCE のビルドは `PATCH /v1/builds/{id}` `{"data":{"type":"builds","id":…,"attributes":{"usesNonExemptEncryption":false}}}`。
- 保守的に declaration を作る場合: 上記 POST (4 attrs + app) → `PATCH /v1/builds/{id}` で relationship 紐付け。
- フランス配信ありなら French declaration 書類が必要 → `availableOnFrenchStore=false` にしてフランスを配信国から外すのが書類回避の唯一路。
- 未確認 (実 API 未実行): POST 直後の state が CREATED のままか自動遷移するか、書類なしで APPROVED になるか、`usesNonExemptEncryption=false` PATCH の挙動。初回は実 GET/PATCH で確認。
