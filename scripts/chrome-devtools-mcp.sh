#!/usr/bin/env bash
# chrome-devtools MCP のラッパー。
# project-scope .mcp.json から呼ばれることを想定。userDataDir をプロファイル名で分離して
# 複数 Claude Code セッションの同時起動 (project 単位の並列) を可能にする。
#
# 使い方 (.mcp.json):
#   {
#     "mcpServers": {
#       "chrome-devtools": {
#         "type": "stdio",
#         "command": "/Users/touri/Documents/Creatives/Developments/Muraki/scripts/chrome-devtools-mcp.sh",
#         "args": ["<profile-slug>"]
#       }
#     }
#   }
#
# 第1引数: プロファイル名 (省略時は "default" = ~/.cache/chrome-devtools-mcp/chrome-profile と互換)
# 残り: chrome-devtools-mcp@latest にそのまま渡す

set -eu

PROFILE="${1:-default}"
shift || true

if [ "${PROFILE}" = "default" ]; then
  USER_DATA_DIR="${HOME}/.cache/chrome-devtools-mcp/chrome-profile"
else
  USER_DATA_DIR="${HOME}/.cache/chrome-devtools-mcp/profiles/${PROFILE}"
fi

CHROME=$(ls -d "${HOME}"/.cache/chrome-devtools-mcp/browsers/chrome/mac_arm-*/chrome-mac-arm64/"Google Chrome for Testing.app"/Contents/MacOS/"Google Chrome for Testing" 2>/dev/null | sort -V | tail -1)

if [ -z "${CHROME}" ] || [ ! -x "${CHROME}" ]; then
  echo "Chrome for Testing が見つかりません。" >&2
  echo "  npx -y @puppeteer/browsers install chrome@stable --path ${HOME}/.cache/chrome-devtools-mcp/browsers" >&2
  exit 1
fi

mkdir -p "${USER_DATA_DIR}"

# --use-mock-keychain: macOS の実 Keychain (Chromium Safe Storage) を使わず決定的な固定鍵で
# cookie を暗号化する。headless 起動時の Keychain 認証ダイアログ (headless では応答不能→復号失敗
# →ログイン cookie が使えない) を回避し、かつ chrome-login.sh の GUI 起動と同じ鍵にして
# ログインセッションを継承可能にする。詳細: knowledge/gotcha/chrome-for-testing-macos-keychain-cookie.md
exec npx -y chrome-devtools-mcp@latest \
  --headless \
  --userDataDir "${USER_DATA_DIR}" \
  --executablePath "${CHROME}" \
  --chromeArg=--use-mock-keychain \
  ${@+"$@"}
