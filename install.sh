#!/bin/bash
#
# MediaCrawler WebUI macOS 原生窗口 —— 一键安装脚本
#
# 做四件事：
#   1. 检查依赖（uv / Node.js / Google Chrome）
#   2. 从官方仓库拉取 MediaCrawler（本项目不打包上游源码）
#   3. 装 Python 依赖 + 构建 WebUI 前端 + 装 pywebview
#   4. 生成可双击启动的 .app
#
# 用法：
#   ./install.sh                      装到 ~/MediaCrawler
#   ./install.sh --dir ~/code/MC      指定安装目录
#   ./install.sh --skip-clone         项目已存在，跳过拉取步骤
#   ./install.sh --app-dir /Applications   把 .app 装到指定位置
#
set -euo pipefail

UPSTREAM_REPO="https://github.com/NanmiCoder/MediaCrawler"
LAUNCHER_HOME="$HOME/.local/share/mediacrawler-launcher"
CONFIG_DIR="$HOME/.config/mediacrawler-launcher"
TARGET_DIR="$HOME/MediaCrawler"
APP_OUT_DIR="$HOME/Applications"
SKIP_CLONE=0

C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'
C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_BOLD=$'\033[1m'

step()  { printf '\n%s==>%s %s%s%s\n' "$C_BLUE" "$C_RESET" "$C_BOLD" "$1" "$C_RESET"; }
ok()    { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
warn()  { printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
die()   { printf '\n  %s✗ %s%s\n\n' "$C_RED" "$1" "$C_RESET" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)        TARGET_DIR="${2:?--dir 需要一个路径}"; shift 2 ;;
    --app-dir)    APP_OUT_DIR="${2:?--app-dir 需要一个路径}"; shift 2 ;;
    --skip-clone) SKIP_CLONE=1; shift ;;
    -h|--help)    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)            die "未知参数：$1（用 --help 看用法）" ;;
  esac
done

[[ "$(uname -s)" == "Darwin" ]] || die "这个脚本只支持 macOS。"

printf '%s\n' "${C_BOLD}MediaCrawler WebUI macOS 原生窗口 —— 安装${C_RESET}"
printf '%s\n' "${C_DIM}上游项目：$UPSTREAM_REPO${C_RESET}"

# --------------------------------------------------------------------------- #
step "1/5 检查依赖"
# --------------------------------------------------------------------------- #
# 双击 .app 时系统给的 PATH 很短，把常见目录补进来
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

UV_BIN="$(command -v uv || true)"
if [[ -z "$UV_BIN" ]]; then
  die "没找到 uv。先装它：
       brew install uv
     或：curl -LsSf https://astral.sh/uv/install.sh | sh"
fi
ok "uv $("$UV_BIN" --version 2>/dev/null | head -1)"

NODE_BIN="$(command -v node || true)"
NPM_BIN="$(command -v npm || true)"
if [[ -z "$NODE_BIN" || -z "$NPM_BIN" ]]; then
  die "没找到 Node.js / npm（构建 WebUI 前端需要）。先装它：
       brew install node"
fi
ok "Node.js $("$NODE_BIN" --version)  npm $("$NPM_BIN" --version)"

CHROME_APP="/Applications/Google Chrome.app"
if [[ -d "$CHROME_APP" ]]; then
  ok "Google Chrome 已安装"
else
  warn "没检测到 Google Chrome。MediaCrawler 靠浏览器登录态抓取，建议先装：
       https://www.google.com/chrome/"
fi

PY_BIN="$(command -v python3 || true)"
[[ -n "$PY_BIN" ]] || die "没找到 python3。"
ok "python3 $("$PY_BIN" --version 2>&1 | awk '{print $2}')"

# --------------------------------------------------------------------------- #
step "2/5 获取 MediaCrawler 源码"
# --------------------------------------------------------------------------- #
if [[ "$SKIP_CLONE" -eq 1 ]]; then
  [[ -f "$TARGET_DIR/main.py" && -f "$TARGET_DIR/api/main.py" ]] \
    || die "--skip-clone 但 $TARGET_DIR 不是 MediaCrawler 目录"
  ok "跳过拉取，使用已有目录 $TARGET_DIR"
elif [[ -f "$TARGET_DIR/main.py" && -f "$TARGET_DIR/api/main.py" ]]; then
  ok "目录已存在且是 MediaCrawler，跳过拉取：$TARGET_DIR"
  warn "想强制更新请先删掉目录，或在里面 git pull"
else
  mkdir -p "$(dirname "$TARGET_DIR")"
  if command -v git >/dev/null 2>&1 \
     && git clone --depth 1 "$UPSTREAM_REPO.git" "$TARGET_DIR"; then
    ok "已 git clone 到 $TARGET_DIR"
  else
    warn "git clone 失败，改用官方 zip 快照下载…"
    ARCHIVE="$(mktemp -t mediacrawler).zip"
    curl -fL --retry 3 -o "$ARCHIVE" \
      "https://codeload.github.com/NanmiCoder/MediaCrawler/zip/refs/heads/main" \
      || die "下载失败。请检查网络，或手动 clone $UPSTREAM_REPO 后加 --skip-clone 重跑。"
    mkdir -p "$TARGET_DIR"
    # macOS 自带 tar 能解 zip，比 unzip 更耐受中文文件名
    tar -xf "$ARCHIVE" -C "$TARGET_DIR" --strip-components=1 \
      || die "解压失败：$ARCHIVE"
    rm -f "$ARCHIVE"
    ok "已下载源码快照到 $TARGET_DIR"
  fi
fi

# --------------------------------------------------------------------------- #
step "3/5 安装 Python 依赖"
# --------------------------------------------------------------------------- #
(cd "$TARGET_DIR" && "$UV_BIN" sync) || die "uv sync 失败，见上方输出"
ok "Python 依赖就绪"

"$UV_BIN" pip install --python "$TARGET_DIR/.venv/bin/python" pywebview \
  || die "安装 pywebview 失败"
ok "pywebview 已安装（原生窗口依赖）"

# --------------------------------------------------------------------------- #
step "4/5 构建 WebUI 前端"
# --------------------------------------------------------------------------- #
if [[ -f "$TARGET_DIR/api/webui/index.html" ]]; then
  ok "前端产物已存在，跳过构建（删掉 api/webui/ 可强制重建）"
else
  ( cd "$TARGET_DIR/webui" && "$NPM_BIN" install && "$NPM_BIN" run build ) \
    || die "前端构建失败，见上方输出"
  [[ -f "$TARGET_DIR/api/webui/index.html" ]] \
    || die "构建完成但没找到 api/webui/index.html，请检查 webui/vite.config.* 的 outDir"
  ok "前端已构建到 api/webui/"
fi

# --------------------------------------------------------------------------- #
step "5/5 安装启动器并生成 .app"
# --------------------------------------------------------------------------- #
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$LAUNCHER_HOME" "$CONFIG_DIR"
cp "$REPO_DIR/launcher/webui_native.py" "$LAUNCHER_HOME/webui_native.py"
chmod +x "$LAUNCHER_HOME/webui_native.py"
ok "启动器已装到 $LAUNCHER_HOME"

cat > "$CONFIG_DIR/config.json" <<JSON
{
  "project": "$TARGET_DIR"
}
JSON
ok "已记录项目路径到 $CONFIG_DIR/config.json"

bash "$REPO_DIR/build_app.sh" --project "$TARGET_DIR" --out "$APP_OUT_DIR" \
  || die "生成 .app 失败"

# --------------------------------------------------------------------------- #
step "自检"
# --------------------------------------------------------------------------- #
if "$TARGET_DIR/.venv/bin/python" "$LAUNCHER_HOME/webui_native.py" --check; then
  :
else
  die "自检未通过，见上方 FAIL 行"
fi

cat <<EOF

${C_GREEN}${C_BOLD}安装完成。${C_RESET}

  启动：双击 ${C_BOLD}$APP_OUT_DIR/MediaCrawler WebUI.app${C_RESET}
        或者：$TARGET_DIR/.venv/bin/python $LAUNCHER_HOME/webui_native.py

  停止：$TARGET_DIR/.venv/bin/python $LAUNCHER_HOME/webui_native.py --stop

  项目目录：$TARGET_DIR
  日志：    $CONFIG_DIR/launcher.log

${C_DIM}首次打开 WebUI 会做环境检测，点「开始使用」即可。
爬取前记得在 config/base_config.py 里改 KEYWORDS，并选择登录方式。
本工具仅供学习研究，请遵守上游 LICENSE（非商业）与各平台使用条款。${C_RESET}

EOF
