#!/usr/bin/env bash
# chrome-devtools MCP は通常 headless で動かす。
# ログインが必要なサイト (Notion 等) のセッションを userDataDir に保存するため、
# このスクリプトで Chrome for Testing を GUI 起動してユーザーが手動ログインする。
#
# 使い方:
#   1. claude (MCP) を停止 — 同一 userDataDir を MCP と GUI で同時に握れない
#   2. ./chrome-login.sh [URL ...]
#   3. 表示された Chrome でログイン → 終了
#   4. claude を再起動 — 以降 headless でもログイン状態が引き継がれる

set -eu

USER_DATA_DIR="${HOME}/.cache/chrome-devtools-mcp/chrome-profile"

CHROME=$(ls -d "${HOME}"/.cache/chrome-devtools-mcp/browsers/chrome/mac_arm-*/chrome-mac-arm64/"Google Chrome for Testing.app"/Contents/MacOS/"Google Chrome for Testing" 2>/dev/null | sort -V | tail -1)

if [ -z "${CHROME}" ] || [ ! -x "${CHROME}" ]; then
  echo "Chrome for Testing が見つかりません。" >&2
  echo "  npx -y @puppeteer/browsers install chrome@stable --path ${HOME}/.cache/chrome-devtools-mcp/browsers" >&2
  exit 1
fi

if pgrep -f "${USER_DATA_DIR}" >/dev/null 2>&1; then
  echo "警告: ${USER_DATA_DIR} を使う Chrome プロセスが既に存在します。" >&2
  echo "       chrome-devtools MCP を停止してから再実行してください。" >&2
  exit 2
fi

mkdir -p "${USER_DATA_DIR}"
exec "${CHROME}" --user-data-dir="${USER_DATA_DIR}" "$@"
