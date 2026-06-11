---
title: .ics import を contentHash dedup + preview/commit 2-phase で実装する標準パターン
category: pattern
tags: [calendar, ics, import, rfc5545, dedup, node-ical, sha256, multipart, title-mapping, privacy]
created: 2026-05-27
project: global
sources:
  - RFC 5545 https://datatracker.ietf.org/doc/html/rfc5545
  - node-ical https://github.com/Apollon77/node-ical
  - jschardet https://github.com/aadsm/jschardet
  - iconv-lite https://github.com/ashtuchkin/iconv-lite
  - Reclaim AI smart categories https://help.reclaim.ai/en/articles/4545084-smart-events-and-categories
  - Calendly Security https://calendly.com/pages/security
related_knowledge:
  - knowledge/pattern/rrule-string-onfly-expand-with-overrides.md  # 取り込んだ RRULE の保存・展開
---

## Context

ユーザーが iPhone / Android / Google / iCloud の `.ics` をアップロードして、自アプリのカレンダー / 予約 / 共有予定に取り込ませる場面。プライバシー対策 (例: 「デート」「就活」「合コン」を共有相手に晒さない) を含めた MVP の実装パターン。

参考プロジェクト: Atender v7 (`projects/atender/.designs/20260527-v7-calendar-rrule-import.md`)、Calendly Sync、Reclaim AI Smart Categories。

## What

### 2-phase flow (preview → commit)

```
[upload] POST /ics-imports                  → multipart, 5MB limit
              ↓ parse, store rawText + contentHash
              ↓ 201 { import: { id, status: "PARSED" }, parsedCount, dedup: false }

[preview] GET /ics-imports/:id/preview     → mapping シミュレーション
              ↓ 200 { importId, events: [{ uid, rawTitle, mappedTitle, visibilityMode }] }

[commit] POST /ics-imports/:id/commit       → mapping 適用 + upsert
              ↓ 200 { committed, skipped, errors[] }

[delete] DELETE /ics-imports/:id           → cascade で関連 Event 全削除
```

### dedup key: `(userId, contextId, contentHash)`

- `contentHash` = SHA-256 of raw bytes
- 同じバイト列を 2 度 upload しても新行は作らず、既存 import を返す (`dedup: true`)
- `contextId` = Atender なら `roomId`、汎用なら「取り込み先コンテナ ID」

```ts
import { createHash } from "node:crypto";

const contentHash = createHash("sha256").update(buf).digest("hex");
const existing = await prisma.icsImport.findFirst({
  where: { userId, contextId, contentHash },
});
if (existing) return { import: existing, dedup: true };
```

### Event 単位の dedup key: `(contextId, externalUid)`

- `externalUid` = RFC 5545 `UID:` 値
- 同一 UID で SEQUENCE が上がっていれば update、同じか古ければ skip
- LAST-MODIFIED でも fallback 比較

```ts
const existing = await prisma.event.findUnique({
  where: { contextId_externalUid: { contextId, externalUid: v.uid } },
});
if (existing) {
  const incomingSeq = v.sequence ?? 0;
  const existingSeq = existing.externalSeq ?? 0;
  if (incomingSeq < existingSeq) return "skip";
  if (incomingSeq === existingSeq && v.lastModified <= existing.externalLastModified) return "skip";
  // update
} else {
  // create
}
```

### エンコーディング正規化

```ts
import jschardet from "jschardet";
import iconv from "iconv-lite";

function normalizeIcs(buf: Buffer): string {
  const detected = jschardet.detect(buf);
  const enc = (detected?.encoding ?? "utf-8").toLowerCase();
  const text = (enc === "utf-8" || enc === "utf8" || enc === "ascii")
    ? buf.toString("utf8")
    : iconv.decode(buf, enc);
  return text.replace(/^﻿/, "");   // BOM strip
}
```

日本語スマホカレンダーの古い export は **Shift-JIS** あり得る、Outlook 旧版は **Win-1252**。必ず autodetect する。

### Floating time (TZ なし) の解釈

`DTSTART:20260527T090000` (Z なし / TZID なし) を **サーバー TZ で解釈する**と本番事故。明示的に「ユーザーの設定 TZ (例: Asia/Tokyo)」として解釈し、その時点で UTC 化:

```ts
function toUtc(d: Date & { tz?: string }): Date {
  if (!d.tz) {
    const jstOffsetMs = 9 * 60 * 60 * 1000;
    return new Date(d.getTime() - jstOffsetMs); // node-ical の Floating Date を JST 壁時計と仮定
  }
  return d; // TZID 付きは node-ical が UTC 化済
}
```

### 機微情報の filter (parse 段)

`.ics` には `DESCRIPTION` / `LOCATION` / `ATTENDEE` が入っていることがある。これらは**保存しない** (parse 時に破棄):

```ts
// 抽出関数では SUMMARY / UID / DTSTART / DTEND / RRULE / EXDATE / RDATE / RECURRENCE-ID / SEQUENCE / LAST-MODIFIED のみ取る
function extractVEvent(v): ParsedVEvent {
  return {
    uid: v.uid,
    summary: v.summary,
    start: toUtc(v.start),
    end: toUtc(v.end),
    rrule: v.rrule?.toString().replace(/^RRULE:/, "") ?? null,
    // DESCRIPTION / LOCATION / ATTENDEE は無視
  };
}
```

### タイトル正規化 (3 種 + デフォルト「全部 → 予定」)

```prisma
model TitleRule {
  id          String  @id
  userId      String
  matchType   String  // EQUALS | CONTAINS | REGEX
  pattern     String
  replaceWith String? // null → "予定"
  visibility  String  // NORMAL | TITLE_MAPPED | BUSY_ONLY
  priority    Int     @default(100)
  isDefault   Boolean @default(false)
}
```

```ts
function applyTitleRules(rawTitle: string, rules: TitleRule[]) {
  // priority 昇順、最初に hit したルールを使う
  for (const r of rules) {
    if (matches(r.matchType, r.pattern, rawTitle)) {
      return { title: r.replaceWith ?? "予定", visibility: r.visibility, ruleId: r.id };
    }
  }
  return { title: rawTitle, visibility: "NORMAL", ruleId: null };
}

function matches(type, pattern, target) {
  if (type === "EQUALS") return target === pattern;
  if (type === "CONTAINS") return target.includes(pattern);
  if (type === "REGEX") {
    try { return new RegExp(pattern).test(target); } catch { return false; }
  }
  return false;
}
```

初回 import 時に「全部 → 予定」(REGEX `.*`, priority 9999, isDefault=true) を自動生成 → 何もルールを定義しなくてもプライバシー保護される。

### Visibility 3 段階

```ts
enum Visibility {
  NORMAL,         // 全員に title をそのまま見せる
  TITLE_MAPPED,   // mapping 適用済、rawTitle は本人のみ
  BUSY_ONLY,      // 全員に "予定あり" のみ、時間枠だけ共有
}
```

API レスポンスで本人と他人の見え方を分岐:

```ts
function visibilityApplied(event, viewerId) {
  const isAuthor = event.authorId === viewerId;
  return {
    ...event,
    title: event.visibility === "BUSY_ONLY" && !isAuthor ? "予定あり" : event.title,
    rawTitle: isAuthor ? event.rawTitle : null,
    description: event.visibility === "BUSY_ONLY" && !isAuthor ? null : event.description,
    recurrenceRule: isAuthor ? event.recurrenceRule : null,
  };
}
```

### rawText を DB に保持 (preview/commit 用)

upload 直後の parse 結果はメモリに置かず、`IcsImport.rawText` (= 正規化済 UTF-8 text) を DB に保存。理由:
- preview → commit のラグでサーバー再起動が起きてもセッション継続
- mapping rule をユーザーが編集してから commit する場合の再 parse 用
- size は 5MB 以下なので肥大しない

SUCCESS 後 7-30 日経過した import の `rawText` を nullify する cron は Phase 1.5 で追加。

## Why

- **2-phase (preview → commit)** は import の信頼性と UX を両立: ユーザーが「何が入ってくるか」を確認してから確定できる、mapping rule の事後追加も preview で確認可能
- **contentHash dedup** は re-upload を冪等にする: ユーザーが同じファイルを 2 回 upload しても DB 行が増えない、ネットワーク不安定時の retry が安全
- **externalUid dedup** は更新を冪等にする: SEQUENCE / LAST-MODIFIED で「進化した分だけ update、退化は skip」
- **タイトル正規化を server で適用**: プライバシー保護の最終ラインを backend が握る。client が visibility ガードを忘れても rawTitle は他人に漏れない
- **DESCRIPTION / LOCATION / ATTENDEE を破棄**: SUMMARY 以外の機微情報を「そもそも持たない」設計でプライバシー事故面を最小化
- **Floating time の明示 TZ 解釈**: サーバー稼働 TZ が変わっても挙動が変わらない、運用環境差異の事故を防ぐ

## How to apply

1. **DB schema は 3 テーブル**: `Import`, `Event`, `TitleRule` を分離。`Import` には rawText を保持し preview/commit を 2-phase で
2. **contentHash (SHA-256) で upload 単位の dedup**、`externalUid` (RFC 5545 UID) で Event 単位の dedup を**両方持つ**
3. **エンコーディング検出 + 変換** は `jschardet` + `iconv-lite`。日本市場なら Shift-JIS / EUC-JP / Win-1252 をカバー
4. **Floating time は app 層で TZ 固定解釈**。サーバー `process.env.TZ` に依存させない
5. **`.ics` から取るのは SUMMARY / UID / DTSTART / DTEND / RRULE / EXDATE / RDATE / RECURRENCE-ID / SEQUENCE / LAST-MODIFIED のみ**。DESCRIPTION / LOCATION / ATTENDEE は破棄
6. **デフォルトルール「全部 → 予定」を user 初回 import 時に auto-create**。何もしないユーザーでもプライバシーが保たれる
7. **REGEX は `new RegExp()` の try/catch で invalid を swallow**。バリデーション失敗で match なし扱い
8. **5MB upper limit を Hono / Express middleware で enforce**。413 で返す、UI で「期間で絞って再 export」案内
9. **visibility 適用は server レスポンス段で実施**。client は受信した値をそのまま表示するだけ
10. **rawText DB 保持の保持期間ポリシー**: 30 日 (or 7 日) で SUCCESS 済 import を nullify するクリーンアップを cron に追加

## 反例 / 限界

- **URL subscribe (webcal:// / HTTPS)** は別パターン: 同 schema (`source=ICS_URL`) で扱えるが、ETag/If-Modified-Since + cron polling + URL 暗号化保存が必要。MVP では file upload に絞り、URL subscribe は Phase 1.5
- **Google OAuth + watch (即時同期)** はさらに別: scopes 審査 + webhook callback + token refresh のサーバー要件あり。サードパーティ依存大きい
- **LLM auto-categorize** (Claude / GPT) は精度高いが推論コストとレイテンシ。MVP は user 定義 rule で十分
- **DESCRIPTION 破棄の方針はユースケース次第**: 会議情報共有が必須のアプリでは保存する。本パターンは「ピアプライバシー優先」場面向け
- **超大量シリーズの import** (1 file に 10000 VEVENT) は parse 自体がメモリ圧。MVP では 5MB cap で実用上ガード、超えるユースケースは別途 stream parse 設計
