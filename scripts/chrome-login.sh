#!/usr/bin/env bash
# chrome-devtools MCP は通常 headless で動かす。
# ログインが必要なサイト (Notion 等) のセッションを userDataDir に保存するため、
# このスクリプトで Chrome for Testing を GUI 起動してユーザーが手動ログインする。
#
# 使い方:
#   1. 同 userDataDir を握る headless Chrome プロセスを kill (Claude Code 自体は止めなくてよい)
#        pkill -f "chrome-devtools-mcp/chrome-profile"   # default
#        pkill -f "chrome-devtools-mcp/profiles/<slug>"  # project-scope
#      ※ このスクリプトは既存プロセスを検出すると abort するので、忘れても安全
#   2. ./chrome-login.sh [--profile <name>] [URL ...]
#        --profile 省略時は user-scope MCP と同じ default プロファイル
#        --profile <slug> 指定で project 単位の userDataDir にログイン
#   3. 表示された Chrome でログイン → 終了 (プロファイルにセッション保存)
#   4. 次の MCP ツール呼び出しで headless が自動再起動 → ログイン状態を引き継ぎ

set -eu

PROFILE=""
URLS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --profile)
      PROFILE="${2:-}"
      shift 2
      ;;
    --profile=*)
      PROFILE="${1#*=}"
      shift
      ;;
    *)
      URLS+=("$1")
      shift
      ;;
  esac
done

if [ -z "${PROFILE}" ] || [ "${PROFILE}" = "default" ]; then
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

if pgrep -f "${USER_DATA_DIR}" >/dev/null 2>&1; then
  echo "警告: ${USER_DATA_DIR} を使う Chrome プロセスが既に存在します。" >&2
  echo "       該当する chrome-devtools MCP セッションを停止してから再実行してください。" >&2
  exit 2
fi

mkdir -p "${USER_DATA_DIR}"
exec "${CHROME}" --user-data-dir="${USER_DATA_DIR}" ${URLS[@]+"${URLS[@]}"}
