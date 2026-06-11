---
title: 場所選択を共通 Sheet (検索 + 地図 + 現在地) として切り出す Nominatim MVP パターン
category: pattern
tags: [ui, map, leaflet, nominatim, geocoding, bottom-sheet, react]
created: 2026-05-27
project: global
sources:
  - https://nominatim.org/release-docs/develop/api/Search/
  - https://operations.osmfoundation.org/policies/nominatim/
  - https://react-leaflet.js.org/
---

## Context

イベント管理 / 待ち合わせ系アプリで「Schedule に場所を設定」「Feature (集合) に場所を設定」「event 作成時に集合場所を設定」など、**場所選択 UI が複数画面で必要**になる。

OMATASE-demo 旧設計では各画面で「inline map + 手入力 label」を別個に配置していたが、Touri 実機 (2026-05-26) で「場所選択が困難すぎる」「地図表示をクリックしたら独立モーダルで場所検索→決定」と fb。各画面で個別 UI を持つと検索/現在地/ピン drag の操作感もバラつく。

## What

**`<LocationPickerSheet>` を共通 Sheet として 1 つだけ作り**、必要画面 (CreateWhere / ScheduleEditSheet / MeetupSheet config / …) から `open + initial + onResolve` で共通呼び出しする。

```tsx
interface LocationPickerSheetProps {
  open: boolean;
  initial?: { lat: number; lng: number; label: string } | null;
  onResolve: (result: { lat: number; lng: number; label: string }) => void;
  onDismiss: () => void;
}
```

内部 UI 構成 (上から):
1. **検索 input** (debounce 500ms → Nominatim `/search?format=json&q=<encoded>&limit=8&accept-language=ja`)
2. **「📍 現在地を使う」 chip** (`navigator.geolocation.getCurrentPosition`, timeout 8s)
3. **検索結果リスト** (8 件まで、tap で地図中心 + label auto-fill)
4. **地図** (`<MapSection>` + draggable Marker、高さ 260px)
5. **場所のラベル input** (検索選択で auto-fill、手動編集可)
6. **header に `[決定]` ボタン** (label 1 文字以上必須)

Nominatim 運用規約:
- `User-Agent: <AppName>/<version> (+<URL>)` 必須
- 1 req/sec ハードリミット → **debounce 500ms + AbortController** で連続入力時の前 request キャンセル、実質「ユーザー 1 人 max 2 req/sec」に抑える
- MVP デモ規模 (低トラフィック) なら client 直叩きで規約内に収まる
- 本格運用化 (同時 100+ アクセス) は server proxy + cache を別 endpoint で挟む

## Why

- **共通化のメリット**: ピン drag / 検索 / 現在地 / label 検証 のロジックを 1 箇所に集約、各画面の利用側は `open / initial / onResolve` の 3 props で済む。UX 操作感も完全統一
- **Sheet として独立させる根拠**: inline map は画面を圧迫する (高さ 200px 占有しても操作しづらい)、独立 Sheet なら 260px 以上取れて検索/結果リスト/ピン操作が同時に見える
- **検索を必須にせずチップで現在地も**: 屋内/初訪問の場所では「現在地ピン→微調整」が最速、検索が要らない場面が多い
- **label を auto-fill + 手動編集可に**: Nominatim display_name は冗長な場合あり (「丸の内, 千代田区, 東京都, 日本」)。auto-fill 後にユーザーが「東京駅 中央口」等に縮めるフローを許可
- **server proxy を MVP では入れない**: MVP デモは低トラフィック、proxy 化は API 形状を変えずに後付け可能 (利用側コードに影響なし)

## How to apply

新規プロジェクトで「場所選択が複数画面で必要」と気づいた瞬間、最初に `<LocationPickerSheet>` を切り出す。チェック:

- [ ] 全 features (CreateWhere / ScheduleEditSheet / MeetupSheet config / …) から同じ Sheet を呼ぶ
- [ ] Nominatim User-Agent ヘッダを必ず付ける (`User-Agent: <AppName>/<version> (+<URL>)`)
- [ ] 検索は debounce 500ms + AbortController で前 request キャンセル
- [ ] 現在地 chip を必ず置く (検索なしルートを残す)
- [ ] ピン drag は (lat,lng) のみ変える (label は drag で変えない、検索 or 手入力で確定)
- [ ] label 空文字での決定は inline error
- [ ] 親 Sheet 上に重ねる場合は **stackLevel=2** (`<Sheet stackLevel={2}>`、§3.6 規約)
- [ ] Phase 2 で本格運用化する場合は server proxy `/api/geocode/search` を後付け、client は同じ Sheet API のまま endpoint だけ差し替える

逆にやってはいけない:

- 各画面で個別に map + 入力欄を作る (×) → 操作感のバラつきと検索ロジック重複の元
- Nominatim を debounce なしで叩く (×) → 1 req/sec policy 違反で IP ban リスク
- reverse geocode (ピン drag で住所自動 fill) を MVP で入れる (×) → reverse は 1 req/sec が より厳しい、ピン drag 頻度と相性悪い
- Map 高さを 160px 以下にする (×) → ピン位置の認識が困難

OMATASE-demo の §7.13 / §12.12 はこのパターンを設計に直接埋め込んだ実例。
