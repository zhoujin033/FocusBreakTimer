#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "这个应用需要在 macOS 上构建和运行。" >&2
  exit 1
fi

if ! xcrun --find clang >/dev/null 2>&1; then
  echo "请先在终端运行 xcode-select --install，完成 Command Line Tools 安装后重试。" >&2
  exit 1
fi

if /usr/bin/pgrep -x FocusBreakTimer >/dev/null; then
  echo "请先从菜单栏退出旧版学习休息倒计时，然后重新运行本脚本。" >&2
  exit 1
fi

bash "$ROOT_DIR/build.sh"
open "$ROOT_DIR/学习休息倒计时.app"
