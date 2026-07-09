---
title: ChatGPT developer mode カスタム MCP コネクタの仕様と OAuth 実態 (2026-07)
category: library
project: global
tags: [chatgpt, mcp, oauth, dcr, cimd, redirect-uri, mcp-apps, developer-mode]
created: 2026-07-07
sources:
  - https://developers.openai.com/api/docs/guides/developer-mode
  - https://developers.openai.com/apps-sdk/build/auth
  - https://developers.openai.com/apps-sdk/build/mcp-server
  - https://developers.openai.com/apps-sdk/build/custom-ux
  - https://community.qlik.com/t5/Official-Support-Articles/Qlik-MCP-and-ChatGPT-error-Invalid-redirect-uri-or-redirect-uri/ta-p/2544958
  - https://community.openai.com/t/auth-dynamic-client-registration-dcr-problem/1379403
  - https://gofastmcp.com/integrations/chatgpt
---

## Context

dandan-app 再設計で ChatGPT developer mode を MCP Apps iframe UI の一級ホストに昇格させる。自前 AS (DCR + PKCE) と噛み合うかの事実確認。

## What

### コネクタ追加 (developer mode)
- 経路: Settings → Apps → Advanced settings → **Developer mode** を ON → 「Create app」で remote MCP の URL を登録。作成物は Drafts 扱い、チャットごとに有効化。
- transport: 「Supported MCP protocols: **SSE and streaming HTTP**」— Streamable HTTP で可 (dandan-mcp の Go サーバ `/mcp` で実績あり)。
- プラン: **Pro / Plus / Business / Enterprise / Education の Web 版**。Free 不可。
- dev mode では search/fetch ツール必須要件なし。write 系ツールは既定でユーザー確認、`readOnlyHint` annotation で read-only 検出。

### OAuth (MCP 認可 spec との噛み合い)
- discovery はフル準拠: 401 → RFC 9728 `/.well-known/oauth-protected-resource` (`resource`, `authorization_servers`, `scopes_supported`) → RFC 8414 AS metadata または OIDC discovery。
- client 登録は 2 方式:
  - **CIMD (Client ID Metadata Documents)** — OpenAI 推奨。client_id = ChatGPT がホストする HTTPS metadata URL (コネクタ固有)。AS metadata に `client_id_metadata_document_supported: true` が必要。token auth は `none` か `private_key_jwt`。
  - **DCR (RFC 7591)** — 引き続きサポート。**コネクタインスタンスごとに registration_endpoint を 1 回だけ呼び、client_id を恒久キャッシュ**する。
- redirect_uri: 現行は **`https://chatgpt.com/connector/oauth/{callback_id}`** (コネクタごとに callback_id が異なる、公式 apps-sdk/build/auth に明記)。旧/静的な `https://chatgpt.com/connector_platform_oauth_redirect` も第三者記事で観測 (Qlik)。DCR 経由なら redirect_uris は登録リクエストに載ってくるのでそれを保存すれば足りるが、prefix 検証するなら `https://chatgpt.com/connector/oauth/` + 旧静的 URL の両方を許容。
- PKCE S256 使用。**RFC 8707 `resource` param を authorize/token 両方に付与**し、AS は access token の `aud` に反映することが要求される。
- ★ gotcha: DCR の client_id はコネクタ単位でキャッシュされ**再登録のリフレッシュ経路が無い** (published app で stale client_id 化 → 作り直しのみ、という報告)。自前 AS は登録済み client を expire/削除しない設計にする。

### instructions / prompts / tool ロード
- server `instructions` は読まれる: 「server-wide guidance such as required tool sequences, shared rate limits, or relationships between tools」に使えと公式明記。コネクタの「refresh」で tools/descriptions/instructions を再取得。
- MCP **prompts を surface する公式記述なし** (FastMCP docs も tools のみ)。prompts 非依存設計が安全 (Codex と同じ制約 → tool 戻り値ステアリング主経路、[[library/remote-mcp-oauth-hosts-2026]] と整合)。
- 遅延ロード (tool search) の公式言及なし。tools は per-app で on/off トグル可。

### MCP Apps (iframe UI) in ChatGPT
- 標準拡張 `io.modelcontextprotocol/ui` をサポート: `ui://` リソース (mime `text/html;profile=mcp-app`) + `_meta.ui.resourceUri` (nested)。legacy alias `_meta["openai/outputTemplate"]` も認識。
- bridge: **`ui/message` (会話への投稿依頼) 対応**、`ui/update-model-context`、iframe からの `tools/call` も対応。→ dandan bridge.js の建て付け (ui/initialize handshake + tools/call + ui/message) はそのまま通る想定。
- CSP: `_meta.ui.csp` の `connectDomains` / `resourceDomains` / `frameDomains`。subframe 許可は directory 審査で厳しめ。`_meta.ui.domain` は **directory 提出時に必須** (サンドボックスは `<domain>.web-sandbox.oaiusercontent.com`)、dev mode カスタムコネクタでは必須の記述なし。
- displayMode: inline / PiP / fullscreen (`window.openai.requestDisplayMode` は ChatGPT 拡張)。iframe サイズ制約はドキュメント記載なし。

## Why

ChatGPT は MCP 認可 spec (9728/8414/7591/PKCE/8707) をフル実装しており、自前 AS + DCR の既存構成と原理的に噛み合う。差分は redirect_uri 許可と `resource`→`aud` 反映、client 登録の恒久性の 3 点に集約される。

## How to apply

- 自前 AS: (1) DCR は現状維持で可、登録 client を失効させない (2) redirect_uri は DCR 申告値を保存 + prefix 許可 `https://chatgpt.com/connector/oauth/` (3) token に `resource` 由来の `aud` を入れ RS 側で audience 検証 (4) 余力があれば CIMD (`client_id_metadata_document_supported`) 対応で DCR キャッシュ問題を回避。
- prompts に機能をゲートさせない。instructions は書けば読まれる。
- iframe UI は標準 MCP Apps のまま書き、`window.openai` 拡張は feature-detect で optional に。
