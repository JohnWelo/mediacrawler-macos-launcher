#!/bin/bash
#
# 卸载 MediaCrawler WebUI 原生窗口启动器
#
# 默认只删「启动器 + .app」，**不动** MediaCrawler 源码目录。
#
# 用法：
#   ./uninstall.sh              删除启动器与 .app
#   ./uninstall.sh --purge DIR  连源码目录一起删（会二次确认）
#
set -euo pipefail

LAUNCHER_HOME="$HOME/.local/share/mediacrawler-launcher"
CONFIG_DIR="$HOME/.config/mediacrawler-launcher"
APP="$HOME/Applications/MediaCrawler WebUI.app"
PURGE_DIR=""

C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'
C_GREEN=$'\033[32m'; C_DIM=$'\033[2m'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge) PURGE_DIR="${2:?--purge 需要一个目录}"; shift 2 ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf '%s✗ 未知参数：%s%s\n' "$C_RED" "$1" "$C_RESET" >&2; exit 1 ;;
  esac
done

removed=0
remove_path() {
  local target="$1"
  if [[ -e "$target" ]]; then
    rm -rf "$target"
    printf '%s✓%s 已删除 %s\n' "$C_GREEN" "$C_RESET" "$target"
    removed=$((removed + 1))
  else
    printf '  %s·%s 不存在，跳过 %s\n' "$C_DIM" "$C_RESET" "$target"
  fi
}

remove_path "$APP"
remove_path "$LAUNCHER_HOME"
remove_path "$CONFIG_DIR"

# 每台机器可能有多个自定义位置，顺手扫一遍 ~/Applications
for extra in "$HOME/Applications"/*.app; do
  [[ -e "$extra" ]] || continue
  if [[ -f "$extra/Contents/MacOS/launch" ]] \
     && grep -q "mediacrawler-launcher/webui_native.py" "$extra/Contents/MacOS/launch" 2>/dev/null; then
    remove_path "$extra"
  fi
done

if [[ -n "$PURGE_DIR" ]]; then
  printf '\n%s⚠️  接下来会删除整个源码目录，不可撤销：%s%s\n' "$C_YELLOW" "$PURGE_DIR" "$C_RESET"
  printf '   这个目录里可能有你抓到的数据、配置改动、登录态。\n'
  printf '   确认请输入 %syes%s，其他任意输入取消：' "$C_YELLOW" "$C_RESET"
  read -r answer
  if [[ "$answer" == "yes" ]]; then
    remove_path "$PURGE_DIR"
  else
    printf '  已取消删除源码目录。\n'
  fi
fi

printf '\n%s完成，共删除 %d 项。%s\n' "$C_GREEN" "$removed" "$C_RESET"
[[ -n "$PURGE_DIR" ]] || printf '%sMediaCrawler 源码目录未改动。%s\n' "$C_DIM" "$C_RESET"
