---
title: 外部ビルドサービス (Xcode Cloud 等) を自前アプリが司令塔として起動・追跡する — 署名なし Webhook は起床合図、相手の採番は別系列で受ける
category: pattern
tags: [xcode-cloud, ci, webhook, polling, numbering, build-number, firebase-app-distribution, idempotency, state-machine, lease]
created: 2026-10-05
project: global
sources:
  - Muraki/projects/wasawasa/.designs/20261005-app-upload-xcode-cloud.md §3, §4, §10
  - Muraki/projects/wasawasa/.knowledge/research-xcode-cloud-trigger.md
  - knowledge/pattern/external-deploy-db-lease-poller.md (土台の run 行 + lease)
---

## Context

管理画面 (wasawasa) のボタンで Xcode Cloud にビルドさせ、成果物を Firebase App Distribution に上げて台帳に登録する。外部ビルドサービスは (a) 起動時に任意の入力を受けない、(b) 完了通知の Webhook に署名が無い、(c) ビルド番号を自分で採番して外部値を受けない、という性質を持つ。自前の台帳には別の番号系列 (ローカル配布用のカウンタ) が既にある。

## What

1. **ビルドサービスには「ビルドするだけ」をさせ、配布・登録は司令塔が持つ**: 成果物を API (`ciArtifacts.downloadUrl`) で取り、配布先の REST に上げる。秘密 (配布先のサービスアカウント) を司令塔の DB 封緘 1 か所に集め、ビルド環境に配布の道具も秘密も置かない。配布先の upload / notes / distribute は冪等 (同じ binary の再 upload は no-op) なので、一時失敗は「次の tick で打ち直す」で済む。非冪等なのは「ビルドの起動」だけで、そこにだけ write-ahead + 結果 3 値 + 一覧照合 (`external-deploy-db-lease-poller`) を使う
2. **署名の無い Webhook は起床合図としてだけ使う**: URL のトークンを定数時間比較 → 合っていれば「この run を次の tick ですぐ見ろ」とメモリに印を付けて `kick()` するだけ。payload の状態 (`COMPLETE` / `SUCCEEDED`) は一切使わず、必ず API で再取得して決める。取りこぼしと別プロセス着信のために低頻度 polling を併用。トークンが漏れて起きるのは「再取得の誘発」だけになるので、URL を画面に出し続けてよく、トークンは Webhook の発火単位 (product) に合わせて 1 つでよい (環境ごとに分けても発火単位と 1 対 1 にならない)。正しいトークンなら本文が壊れていても 2xx を返す (相手は 2xx 以外を再送し続ける)
3. **相手の採番は別系列として受け、自分の台帳に混ぜない**: 成果物の表に `number_source` (ledger / external) を持たせ、一意制約を部分 unique 2 本に分ける (台帳系 = (project, number)、外部系 = (project, 外部の採番単位 = product, number))。外部の番号を台帳に `used` で入れると「n ≥ next なら next = n + 1」の規則でカウンタが外部の帯に引っ張られる。台帳系の一意には `number_source IS NULL` の行も含め、rolling update 中の旧コードの INSERT を壊さない
4. **番号の衝突は DB ではなく外部で起きる**: 配布先 (Firebase は同じ版 + 番号の upload を既存 release の上書きとして扱う) と端末 (同じ CFBundleVersion を区別できない)。だから (a) 外部の次番号を一度だけ大きな帯 (例 10000) に設定して帯を分け、(b) それでも重なった時のために配布先へ上げる前に「同じ版 + 番号の既存」を照合して止める。照合は write-ahead の印 (`upload_started_at`) がある run では飛ばす (自分の前回の upload を相手と誤認しない)
5. **「最新」を番号で決めていた導出を全部洗い出す**: 1 系列なら番号の大小 = 登録順だったが、2 系列では逆転する。「今入れるべき成果物」「一覧の並び」は作成時刻 (同時刻は番号) に置き換える。番号の大小に意味がある機能 (ビルド番号の下限で古いクライアントを締め出す等) は系列をまたぐと無意味になるので、注記するか系列ごとに限る
6. **成果物は取ってから検査する**: export の種類 (Ad Hoc / Development / App Store) をファイル名で当てず、zip の中の `ExportOptions.plist` の `method` (`release-testing` = Xcode 15.3 以降の Ad Hoc) で判定し、`DistributionSummary.plist` の番号と bundle id を run と照合する (ローカル配布スクリプトの検査と同じ保証)。ダウンロード URL は origin の許可リスト + リダイレクトの各 hop も検査、認証ヘッダを付けない (署名 URL)

## Why

- 外部サービスに配布まで任せると、秘密が 2 か所に散り、失敗が「ビルド失敗」1 種類に潰れ、配布 URL を stdout から grep する脆さが入る。司令塔が持てば段階ごとの理由・再試行・キャンセルが台帳と通知に乗る
- 署名なし Webhook の payload を信用すると URL を知る者が完了を偽装できる。再取得すれば信頼の根は API キーだけになる
- 外部の採番は変えられない。止めても「配布はされたが台帳に無い」状態が残るだけなので、受けて別系列にするのが唯一の整合する形

## How to apply

- 設計 doc に「番号を使う箇所の全数表」(`grep buildNumber|build_number` の結果を 1 行ずつ、問題と対応) を置く。導出 (最新・並び・下限) を見落とすと 2 系列化で静かに壊れる
- 外部の未確認事項 (成果物の形・Ad Hoc の有無・URL の認証・番号の一致) は実装前のスパイクとして番号付きで列挙し、結果で doc を置換してから実装に入る。成果物が出ない場合のフォールバック (ビルドの中で自分で export して司令塔の取り込み API に送る) を条件付きのフェーズとして持つ
- 負のコントロール: 「Webhook の本文を信用する」「トークン照合を消す」「export の method 判定を消す」「上書きの照合を消す」でそれぞれ赤になるテストを用意する
- 関連: [[pattern/external-deploy-db-lease-poller]] (run 行・lease・結果不明)、[[library/xcode-cloud-asc-api-2026]] (Xcode Cloud API の仕様)、[[pattern/monotonic-number-ledger-allocate]] (台帳の規則)
