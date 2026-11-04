#!/bin/bash
#
# 从一份已安装好的 MediaCrawler 生成可双击的 macOS .app
#
# 生成的 .app 只做一件事：用项目的 venv 跑原生窗口启动器。
# 不含任何源码副本——它指向你磁盘上已有的那份 MediaCrawler。
#
# 用法：
#   ./build_app.sh                                  自动探测项目目录
#   ./build_app.sh --project ~/MediaCrawler         指定项目目录
#   ./build_app.sh --out /Applications              装到 /Applications
#   ./build_app.sh --name "MC 抓取器"               自定义应用名
#
set -euo pipefail

APP_NAME="MediaCrawler WebUI"
PROJECT=""
OUT_DIR="$HOME/Applications"
LAUNCHER="$HOME/.local/share/mediacrawler-launcher/webui_native.py"

C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_DIM=$'\033[2m'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:?--project 需要一个路径}"; shift 2 ;;
    --out)     OUT_DIR="${2:?--out 需要一个路径}"; shift 2 ;;
    --name)    APP_NAME="${2:?--name 需要一个名字}"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         printf '%s✗ 未知参数：%s%s\n' "$C_RED" "$1" "$C_RESET" >&2; exit 1 ;;
  esac
done

die() { printf '%s✗ %s%s\n' "$C_RED" "$1" "$C_RESET" >&2; exit 1; }

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

# --------------------------------------------------------------------------- #
# 定位项目
# --------------------------------------------------------------------------- #
if [[ -z "$PROJECT" ]]; then
  PY="$(command -v python3 || echo /usr/bin/python3)"
  PROJECT="$("$PY" "$LAUNCHER" --list 2>/dev/null || true)"
fi
[[ -n "$PROJECT" ]] || die "找不到 MediaCrawler 目录，请用 --project 指定"
PROJECT="$(cd "$PROJECT" 2>/dev/null && pwd)" || die "目录不存在：$PROJECT"
[[ -f "$PROJECT/main.py" && -f "$PROJECT/api/main.py" ]] \
  || die "不是 MediaCrawler 项目（缺 main.py 或 api/main.py）：$PROJECT"
[[ -x "$PROJECT/.venv/bin/python" ]] \
  || die "项目缺虚拟环境，先在项目目录执行 uv sync：$PROJECT/.venv/bin/python"
[[ -f "$LAUNCHER" ]] \
  || die "启动器不存在：$LAUNCHER（先跑 install.sh）"

# uv 必须进 .app 的 PATH：WebUI 后端会以命令名 uv 拉起爬虫
UV_BIN="$(command -v uv || true)"
[[ -n "$UV_BIN" ]] || die "PATH 里没有 uv，无法生成启动器"
UV_DIR="$(dirname "$UV_BIN")"

# --------------------------------------------------------------------------- #
# 建 .app 骨架
# --------------------------------------------------------------------------- #
APP="$OUT_DIR/$APP_NAME.app"
mkdir -p "$OUT_DIR"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# --- 可执行入口 ---------------------------------------------------------- #
# 用引号 heredoc（不展开变量）+ 占位符替换，避免 $PATH / $1 被外层提前展开
cat > "$APP/Contents/MacOS/launch" <<'LAUNCH'
#!/bin/bash
# 由 build_app.sh 生成。改动会被覆盖。
#
# 双击 .app 时系统只给极简 PATH（没有 ~/.local/bin、没有 Homebrew），
# 所以这里必须把 uv 所在目录显式补上，否则 WebUI 的「环境检测」会报
# [错误] uv command not found —— 后端是以命令名 uv 去拉起爬虫的。
export PATH="__UV_DIR__:/opt/homebrew/bin:/usr/local/bin:$PATH:/usr/bin:/bin:/usr/sbin:/sbin"

PROJECT="__PROJECT__"
LAUNCHER="__LAUNCHER__"
PY="$PROJECT/.venv/bin/python"

fail() {
  /usr/bin/osascript -e "display alert \"__APP_NAME__\" message \"$1\" as critical" >/dev/null 2>&1
  exit 1
}

[ -x "$PY" ] || fail "找不到项目虚拟环境：$PY。请在项目目录执行 uv sync，或重跑 install.sh。"
[ -f "$LAUNCHER" ] || fail "找不到启动器：$LAUNCHER。请重跑 install.sh。"
[ -f "$PROJECT/api/webui/index.html" ] || fail "缺少 WebUI 构建产物。请在 webui/ 目录执行 npm install && npm run build。"

# --project 显式传入，让 .app 自包含，不依赖 ~/.config 里的配置
exec "$PY" "$LAUNCHER" --project "$PROJECT" "$@"
LAUNCH

# sed 替换前先把会干扰分隔符的字符转义
esc() { printf '%s' "$1" | /usr/bin/sed 's/[&|\\]/\\\\&/g'; }

/usr/bin/sed -i '' \
  -e "s|__UV_DIR__|$(esc "$UV_DIR")|g" \
  -e "s|__PROJECT__|$(esc "$PROJECT")|g" \
  -e "s|__LAUNCHER__|$(esc "$LAUNCHER")|g" \
  -e "s|__APP_NAME__|$(esc "$APP_NAME")|g" \
  "$APP/Contents/MacOS/launch"

chmod +x "$APP/Contents/MacOS/launch"

# --- Info.plist --------------------------------------------------------- #
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>__APP_NAME__</string>
    <key>CFBundleDisplayName</key>     <string>__APP_NAME__</string>
    <key>CFBundleIdentifier</key>      <string>__BUNDLE_ID__</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>launch</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>  <string>12.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>LSBackgroundOnly</key>        <false/>
</dict>
</plist>
PLIST

# 名字里带中文/空格也能得到合法 bundle id
# 注意：macOS 自带的是 BSD sed，基本正则不支持 \+，必须用 -E
SLUG="$(printf '%s' "$APP_NAME" | tr '[:upper:]' '[:lower:]' \
        | /usr/bin/sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
[[ -n "$SLUG" ]] || SLUG="launcher"
BUNDLE_ID="local.mediacrawler.${SLUG}"

/usr/bin/sed -i '' \
  -e "s|__APP_NAME__|$(esc "$APP_NAME")|g" \
  -e "s|__BUNDLE_ID__|$(esc "$BUNDLE_ID")|g" \
  "$APP/Contents/Info.plist"

plutil -lint "$APP/Contents/Info.plist" >/dev/null \
  || die "Info.plist 校验失败"

# --- 图标 ---------------------------------------------------------------- #
ICON_SRC=""
for candidate in \
  "$PROJECT/api/webui/logos/my_logo.png" \
  "$PROJECT/docs/static/images/logo.png" \
  "$PROJECT/api/webui/logos/github.png"
do
  [[ -f "$candidate" ]] && { ICON_SRC="$candidate"; break; }
done

if [[ -n "$ICON_SRC" ]] && command -v iconutil >/dev/null 2>&1; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null 2>&1
    sips -z $((size * 2)) $((size * 2)) "$ICON_SRC" \
      --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null 2>&1
  done
  if iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
    ICON_NOTE="$(basename "$ICON_SRC")"
  else
    ICON_NOTE="生成失败，使用系统默认图标"
    /usr/bin/sed -i '' '/CFBundleIconFile/,+1d' "$APP/Contents/Info.plist"
  fi
  rm -rf "$(dirname "$ICONSET")"
else
  ICON_NOTE="未找到图标源，使用系统默认图标"
  /usr/bin/sed -i '' '/CFBundleIconFile/,+1d' "$APP/Contents/Info.plist"
fi

# --------------------------------------------------------------------------- #
# 注册到 LaunchServices，让 Finder / 聚焦立刻认得它
# --------------------------------------------------------------------------- #
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP" 2>/dev/null || true

printf '%s✓%s 已生成 %s\n' "$C_GREEN" "$C_RESET" "$APP"
printf '  %s项目：%s%s\n' "$C_DIM" "$PROJECT" "$C_RESET"
printf '  %s图标：%s%s\n' "$C_DIM" "$ICON_NOTE" "$C_RESET"
printf '  %suv：  %s%s\n' "$C_DIM" "$UV_BIN" "$C_RESET"

# 装到 /Applications 时提醒一次
case "$OUT_DIR" in
  /Applications) printf '  %s已装到系统「应用程序」文件夹%s\n' "$C_DIM" "$C_RESET" ;;
  *) printf '  %s双击打开，或拖到「应用程序」文件夹%s\n' "$C_DIM" "$C_RESET" ;;
esac
