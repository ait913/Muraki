---
title: Sign in with Google / Sign in with Apple ボタンのブランド規約 (2026-07 現行)
category: library
project: global
tags: [auth, branding, google-signin, sign-in-with-apple, app-store-review, ios, web, assets]
created: 2026-07-16
sources:
  - https://developers.google.com/identity/branding-guidelines
  - https://developers.google.com/identity/images/signin-assets.zip
  - https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple
  - https://developer.apple.com/app-store/review/guidelines/
  - https://devimages-cdn.apple.com/design/resources/download/Logo-Sign-in-with-Apple.dmg
  - https://developer.apple.com/documentation/signinwithapplerestapi/request-an-authorization-to-the-sign-in-with-apple-server.
  - https://developer.apple.com/documentation/signinwithapple/configuring-your-environment-for-sign-in-with-apple
  - https://developer.apple.com/tutorials/data/ja-JP/design/human-interface-guidelines/sign-in-with-apple.json
  - https://fonts.google.com/download/list?family=Google%20Sans
  - https://fonts.google.com/metadata/fonts/Google+Sans
---

## Context

ログイン画面に Google / Apple のソーシャルボタンを並べる時、各社のブランド規約が「塗り・フォント・ロゴ・文言」を縛る。自前デザイントークンで統一しようとすると規約と衝突する。2026-07-16 に一次ソースを全て実取得して確定した内容。

## What

### Google (branding-guidelines, Last updated 2026-07-07)

- **G ロゴは 2025 世代の「gradient super G」**。原文: *"It must be the standard color version (the standard color gradient super G logo)"*。旧来のフラット4色 G は **outdated として明示的に禁止** (*"Don't: Create your own icon for the button or use an outdated Google 'G' for the button"*)。**自前で近似描画も明確に禁止**。
- 公式アセット: `https://developers.google.com/identity/images/signin-assets.zip` (855KB, 認証不要)。中身は **ボタン丸ごと** の PNG(@1x〜@4x)/SVG × Theme{Light,Neutral,Dark} × Shape{Square,Pill} × text{Yes,No} × Platform{iOS, Android+Web}。**素の G 単体ファイルは同梱されていない** → 原文は *"If you need to create your own custom size Google logo, start with any of the logo sizes included in the download bundle"* (= バンドルから抽出せよ)。素の G は `https://developers.google.com/identity/images/g-logo.png` (200x204, 透過, 同じ gradient 世代) でも取れる。
- 許容テーマは3つのみ。**それ以外の色地に color G を置くのは禁止** (*"Don't: Put the standard color Google 'G' icon on a colored background other than light, dark, or neutral"*):
  | Theme | Fill | Stroke | Font color |
  |---|---|---|---|
  | Light | `#FFFFFF` | `#747775` 1px inside | `#1F1F1F` |
  | Dark | `#131314` | `#8E918F` 1px inside | `#E3E3E3` |
  | Neutral | `#F2F2F2` | なし | `#1F1F1F` |
- モノクロ G も禁止 (*"Don't: Use monochrome versions of the Google 'G'"*)。ロゴ単体をボタン境界・文言なしで置くのも禁止。
- 文言: *"Sign in with Google", "Sign up with Google", or "Continue with Google"* を推奨。**ローカライズは明示的に許可** (*"Localization of this text ... is permitted and encouraged"*)。「Google」単体をラベルにするのは禁止。
- **★ 公式アセットは英語専用 = 日本語 UI では使えない (2026-07-16 実測)**。規約は *"The SVG format also makes it possible for you to edit the Sign in with Google text to the language of your app or website"* と書くが、**現行バンドルの SVG のテキストはアウトライン化されたパスで編集不可** (`<text>` 要素 0 個 / `font-family` 属性 0 個 / テキストは `fill="#1F1F1F"` の単一 path、`d` 長 13,128 文字)。PNG も英語焼き込み。⇒ **日本語ボタンを作る手段はカスタムボタンのみ**。規約自身が localize を推奨している以上、カスタムボタンが想定された正道。
- **公式 SVG のジオメトリ実測** (`iOS/SVG/Light/Theme=Light, Show text=Yes, Shape=Square, Platform=iOS.svg`): `width="188" height="44"` / `fill="white"` / `stroke="#747775"` / G の mask が `x="16" y="12" width="20" height="20"` → **iOS spec (高さ44 / leading16 / ロゴ20 / 縦中央) がアートワーク自身で裏付けられる**。角丸は提供画像が 4 (Square)。**カスタムボタンの角丸に規定は無い**。
- **`g-logo.png` (200x204, 透過) は bundle 内の G と同一世代の gradient super G** (全周サンプル一致を実測: 180° (17,188,95) vs (14,188,95) / 270° (255,208,16) vs (255,209,15))。ただし **正方でない (アスペクト 0.98)** ので 20x20 に固定リサイズすると 2% 歪み *"preserve the aspect ratio"* 違反 → **高さ20 / 幅 auto** で使う。
- カスタムボタンのフォント規定: **Google Sans Medium 14/20**。padding 実測 (規約の spec 画像より):
  - iOS: 高さ44 / leading 16 / gap 12 / trailing 16 / ロゴ 20x20 / icon-only 44x44 radius 4
  - Android+Web: 高さ40 / leading 12 / gap 10 / trailing 12 / ロゴ 20x20 / icon-only 40x40 radius 4
  - (注: iOS spec 画像のフォント表記だけ "Roboto Medium" と本文 "Google Sans Medium" が食い違う。画像が古い可能性)
- サイズは拡縮可だが **アスペクト比維持必須**。
- **並置規定**: *"The Sign in with Google button should be displayed at least as prominently as other third party sign-in options. For example, buttons should be approximately the same size and have similar visual weight."*
- 規約外利用は書面同意が必要 (*"Use of Google brands in ways not expressly covered by this document is not allowed without prior written consent from Google"*)。**public repo へのアセット同梱の可否は一次ソースに記述なし = 不明**。
- **Google Sans のライセンス = SIL OFL 1.1 (2026-07-16 確定)**。3 系統の一次ソースで確認: (1) 公式 download manifest `https://fonts.google.com/download/list?family=Google%20Sans` の `manifest.files` に **`OFL.txt` が同梱** (*"This Font Software is licensed under the SIL Open Font License, Version 1.1."*)、(2) `https://fonts.google.com/metadata/fonts/Google+Sans` → `"license":"ofl","isOpenSource":true`、(3) ttf 実 DL して name table **ID 13** に同じ OFL 文言。
  - copyright (name ID 0) = `Copyright 2025 The Google Sans Project Authors (github.com/googlefonts/googlesans)`。**この upstream repo は 404 (非公開)**。`google/fonts` コレクション repo に無い (`ofl/googlesans` 404) のは事実だが **OFL 付与を否定しない** — 参照先 repo が違うだけ。なお `ofl/googlesanscode` は 200 で存在する。
  - **Reserved Font Name の宣言なし** → サブセット化して**同名のまま再配布可**。
  - 一覧 API `https://fonts.google.com/metadata/fonts` の `license` は**全フォントで null** なのでライセンス判定に使えない (**個別**エンドポイント `/metadata/fonts/<Family>` を使う)。
  - **日本語グリフは無い**。`coverage` は latin/greek/cyrillic/devanagari/thai 等のみで **CJK サブセット非収録** → 「Google で続ける」は Latin の "Google" だけが Google Sans、JP は fallback で描画される。
  - Latin サブセット化 (実測 1.98MB → **49,204 bytes / 389 glyphs**、PostScript 名と OFL 表記を保持):
    ```sh
    python3 -m fontTools.subset GoogleSans-Medium.ttf --unicodes="U+0020-007E" \
      --output-file=GoogleSans-Medium-Latin.ttf --name-IDs="*" --name-legacy --layout-features="*"
    ```

### Apple HIG (Sign in with Apple, 最終改訂 2022-09-14)

- **カスタムボタンは明示的に許可されている**。原文: *"If your interface requires it, you can create a custom Sign in with Apple button for iOS, macOS, or the web. For example, you may want to align logos across multiple sign-in buttons, use buttons that display only a logo, or adjust the button's font, bezel, or background appearance to coordinate with your UI."* → **「純正ボタン以外は審査違反」は誤り**。ただし *"App Review evaluates all custom Sign in with Apple buttons."*
- ロゴは **必ず Apple Design Resources のアートワークを使う** (*"Use only the logo artwork downloaded from Apple Design Resources; never create a custom Apple logo."*)。直リンク (認証不要, 200 OK): `https://devimages-cdn.apple.com/design/resources/download/Logo-Sign-in-with-Apple.dmg` (PNG/PDF/SVG, black+white)。
- カスタムボタンで **変えてはいけない**もの: タイトル (`Sign in with Apple` / `Sign up with Apple` / `Continue with Apple` の3択のみ)、一般形状 (logo+text は必ず矩形)、**ロゴとタイトルの色 (両方 black か両方 white。カスタム色禁止)**。
- **★ 日本語タイトルは Apple 自身が規定 (2026-07-16 確定)**。**ja-JP 版 HIG** 原文: 「タイトル。「**Appleでサインイン**」、「**Appleでサインアップ**」、または「**Appleで続ける**」のみを使用すること。」→ **日本語ローカライズは可**で、正式表記は助詞前後にスペース無し (「Apple で続ける」ではなく **「Appleで続ける」**)。
  - **ローカライズ版 HIG の JSON パス**: `https://developer.apple.com/tutorials/data/<locale>/design/human-interface-guidelines/<slug>.json` (例 `.../data/ja-JP/design/...`)。`?language=` や `Accept-Language` では切り替わらない (英語のまま)。`availableLocales` は `en-US, ja-JP, ko-KR, zh-CN`。
- **★ stroke (bezel) の色は非規制**: 規制対象は *"Logo and title colors"* のみ。*"Button bezel and shadow. For example, you can use a stroke to emphasize the button bezel"* → **Apple ボタンの outline を Google Light の `#747775` に合わせて外装をピクセル一致させられる**。
- **★ Apple 43% と Google 14/20 は同一ボタン高で両立しない (証明)**: Apple は title = 高さ×43% (必須)、Google は 高さ44 で 14pt (= 31.8%) → **ボタン高を何にしても Apple の title は Google の約1.36倍**。Apple を14ptにすると高さ33ptで *"no smaller than other sign-in buttons"* 違反、Google を19ptにすると高さ60pt必要で循環。⇒ **両社規約順守下でフォントサイズ統一は不可能**。高さ **44** は「Apple HIG の実例値 (44/19)」「Google の iOS リファレンス高」「iOS 最小タップ領域」が一致する唯一の値でスケーリング不要。
- **ロゴ配置**: *"Match the height of the logo file to the height of the button."* / *"Don't crop"* / *"Don't add vertical padding"* → **ロゴファイルはボタン全高で配置** (padding はファイル内蔵)。*"**Inset the logo if necessary.** If you need to horizontally align the Apple logo with other authentication logos, you can adjust the space between the logo and the button's leading edge."* → **他社ロゴとの左端揃えを明示的に許可**。small/medium/large の3サイズは *"so you can match logo sizes in all the sign-up buttons you display"* が目的。
- カスタムボタンで **変えてよい**もの: タイトルのフォント (weight/size も)、タイトルの case、**背景の見え方 (ただし全体色は black か white のまま。微妙な texture/gradient は可)**、角丸、bezel/shadow。
- 比率規定: タイトルのフォントサイズはボタン高さの **43%** (= ボタン高さ = フォントサイズの233%)。**HIG の実例画像 alt に確定値**: 高さ44→**19pt** / 高さ56→**24pt**。原文 *"Regardless of the font you choose, the title and button height ... need to use the same proportions that the system uses"* (必須語)。ただし *"**Prefer the system font** for the title"* (推奨語) なのでフォント変更自体は可。最小 **140x30pt**、周囲マージン ≥ 高さの1/10、タイトル右マージン ≥ 幅の8%。HIG の実例画像は `left-aligned-correct-proportions-*.png` = **左揃えを明示**。
- PNG は **44pt 高のボタン専用**。それ以外の高さは SVG/PDF を使う。logo-only は常に 1:1、パディング込みなので追加パディング禁止・crop 禁止。
- **並置規定**: *"Prominently display a Sign in with Apple button. Make a Sign in with Apple button no smaller than other sign-in buttons, and avoid making people scroll to see the button."*

### App Store Review Guideline 4.8 (Last Updated: 2026-06-08)

- **現行文面に "Sign in with Apple" という語は無い**。要件は feature ベース: サードパーティ/ソーシャルログイン (Google Sign-In 等) で primary account を作る/認証するアプリは、以下3条件を満たす **another login service** を equivalent option として提供しなければならない:
  1. データ収集を name と email address に限定する
  2. **アカウント設定時にメールアドレスを非公開にできる**
  3. 広告目的の app 内 interaction 収集を同意なくしない
- 免除条件に *"Your app exclusively uses your company's own account setup and sign-in systems"* があるが、**Google を併設した時点で "exclusively" が崩れて免除は効かない**。
- **自前 Magic Link は条件2を満たさない** (実アドレス必須・relay なし) → Google を出す iOS アプリは事実上 SIWA が必要。
- 4.8 は App Store 配布アプリの規約。**独立した Web SPA は対象外**。

### Sign in with Apple の Web (Service ID) 経路

- 認可 endpoint 原文: *"response_mode: ... If you requested any scopes, the value must be `form_post`."* / *"redirect_uri: ... must use the HTTPS protocol, include a domain name, can't be an IP address or localhost"* → **localhost で開発できない**。
- Service ID が必須 (*"You must use a unique identifier — a Services ID — to register each web service that supports Sign in with Apple authentication"*)。**ドメインの登録 + 検証が必須** (*"you must register and verify all top-level domains and subdomains that incorporate Sign in with Apple"*)。Individual アカウントは **URL 10本まで**。
- 注意: *"For users to authenticate with your web service, you must have an existing app in the App Store that uses Sign in with Apple."* → 字面上は App Store 公開が要るように読める。**atender (TestFlight のみ・未公開) で実測したところ authorize endpoint は 200 + sign-in ページを返した**が、これが証明するのは **Return URL 登録済み + ドメイン検証通過**までで、**実ユーザーが同意まで完走して callback が成立するかは未検証** (プローブは同意画面の手前まで)。この条項が後段で効く可能性は残る。
- **★ 実測プローブ — ポータルにログインせず Return URL 登録の有無を確認する方法** (2026-07-16, atender):
  ```sh
  # 登録済みの redirect_uri → HTTP 200 + 本物の "Sign in to Apple Account" ページ (131KB)
  curl -sG "https://appleid.apple.com/auth/authorize" \
    --data-urlencode "client_id=<Service ID>" \
    --data-urlencode "redirect_uri=https://<api-domain>/api/auth/callback/apple" \
    --data-urlencode "response_type=code id_token" \
    --data-urlencode "response_mode=form_post" \
    --data-urlencode "scope=name email" --data-urlencode "state=probe"
  # 対照群: redirect_uri=https://evil.example.com/cb → HTTP 403 Forbidden (146 bytes)
  ```
  対照群が 403 で弾かれるので 200 は偶然でない。**Apple Developer ポータルの GUI にアクセスできない AI でも、登録状態とドメイン検証の通過を確定できる。**

- **Private Email Relay**: relay アドレス (`@privaterelay.appleid.com`) 宛にメールを出すなら送信ドメインを Apple に email source として登録 + SPF 必須。Individual は 32 sources まで。
  - **★ Apple が見るのは From ヘッダでなく envelope sender (= MAIL FROM / Return-Path / bounce アドレス) のドメインで、しかも完全一致を要求する**: *"The domain in the envelope sender ... must be registered in the Domains section ... This domain must pass SPF validation, and the registered domain and envelope sender domain must match exactly."*
  - → **Resend/SES 構成では登録すべきは `send.<domain>` であって `<domain>` ではない**。Resend はドメイン設定時に `send.<domain>` に `v=spf1 include:amazonses.com ~all` と `feedback-smtp.<region>.amazonses.com` の MX を張る (= SES custom MAIL FROM)。apex には DKIM (`resend._domainkey.<domain>`) だけが載り **SPF は無い**ので、apex を見て「SPF が無い」と誤判定しやすい。
  - **要否の判定は「送信経路が実在するか」で決める**: relay ユーザーのアカウントメアドは relay アドレスになるが、**アプリが Magic Link しか送らないなら送信経路は実質存在しない** (本人は自分の relay アドレスを知らないのでメール欄に打てず、次回も SIWA ボタンで入る)。atender は `resend.emails.send` が `magicLink.sendMagicLink` 内の 1 箇所のみのため、**2026-07-16 時点では登録不要と判断して見送った**。通知・リマインダー等を足した瞬間に relay ユーザーだけ bounce するので、**メール送信を増やすときに再確認すること**。

### better-auth (1.6.11) の Apple web 対応状況

`@better-auth/core/src/social-providers/apple.ts` が `responseMode: "form_post"` + `responseType: "code id_token"` を既に送っている。`/callback/:id` は `method: ["GET","POST"]` で、**POST を受けたら同 URL の GET に 302 する** (`dist/api/routes/callback.mjs`) — これにより SameSite=Lax の state cookie がクロスサイト POST で落ちる問題を回避している (Lax はクロスサイトでもトップレベル GET ナビゲーションには送られる)。`originCheckMiddleware` は `if (!(forceValidate || useCookies)) return` で cookie ヘッダの無いリクエストを素通しするため Apple の POST は 403 にならない。`formCsrfMiddleware` (cross-site navigate をブロック) は sign-in/sign-up にしか付いていない。→ **Apple web は追加コードなしで通る設計**。必要なのは Apple 側の Service ID Return URL 登録のみ。

## Why

- Google と Apple の規約は「塗り」の自由度をほぼ潰す: Google は light/dark/neutral の3択、Apple は black/white の2択。**両方を自前 accent 色に揃えることは規約上不可能**。統一は「同一ジオメトリ + 等間隔スタック」でしか達成できない。
- 一方 **フォント統一は Apple 側では可能** (カスタムボタンでフォント変更は明示的に許可)。「純正ボタンだからフォントは変えられない」は `SignInWithAppleButton` を使った場合の制約であって、規約上の制約ではない。
- 4.8 が feature ベースになったことで「SIWA 必須」は文面上の帰結ではなく実務上の帰結。ただし条件2を満たす代替が現実にほぼ SIWA しかないため結論は同じ。

## How to apply

1. **G ロゴ**: `signin-assets.zip` を落とし、必要な Theme/Shape/text の**ボタン画像をそのまま使う**のが最安全。カスタムボタンに G だけ載せるなら SVG から G を抽出 (バンドル起点は規約が明示的に許可)。**自前描画・旧フラット4色 G は禁止**。
2. **Apple ロゴ**: `Logo-Sign-in-with-Apple.dmg` から。SVG/PDF を使えば任意高さ可。PNG は 44pt 専用。
3. **塗りの現実解** (light テーマ): Apple=black or white-outline / Google=Light(白+#747775 border) or Neutral(#F2F2F2) / 自前メール=accent 自由。Apple と Google を両方 outline 系に寄せると2色に減らせる。
4. iOS で Google ボタンの高さを 48 にするなら、公式ボタン画像は縦横比維持で拡縮 (高さ44基準 → 48 は約1.09倍) するか、カスタムボタン規定 (Google Sans Medium 14/20, leading16/gap12/trailing16, ロゴ20pt) に従う。
5. Apple web を足すなら: Service ID に Return URL `https://<api-domain>/api/auth/callback/apple` を登録 + ドメイン検証。**localhost 不可なので開発は本番ドメイン or トンネル必須**。Magic Link を送っているなら Private Email Relay の email source 登録も忘れない。
