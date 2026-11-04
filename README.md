# MediaCrawler WebUI · macOS 原生窗口启动器

把 [MediaCrawler](https://github.com/NanmiCoder/MediaCrawler) 的 WebUI 装进一个 **macOS 原生窗口**，
双击就能用，不用开终端、不用记端口、关窗即停服务。

> **这个仓库不含 MediaCrawler 的任何源码。**
> 它只提供启动器和安装脚本，运行时调用你自己从[官方仓库](https://github.com/NanmiCoder/MediaCrawler)拉下来的那一份。
> 使用 MediaCrawler 必须遵守上游的 [NON-COMMERCIAL LEARNING LICENSE 1.1](https://github.com/NanmiCoder/MediaCrawler/blob/main/LICENSE)（非商业学习用途）。

---

## 它解决什么问题

原项目的 WebUI 官方用法是这样：

```shell
uv run uvicorn api.main:app --port 8080      # 终端 1
cd webui && npm run dev                      # 终端 2
```

然后手动打开浏览器、输入 `localhost:5173`，用完还得回终端 `Ctrl-C`。
日常用起来有三个摩擦点：**要开两个终端**、**要记端口**、**浏览器标签页和一堆杂事混在一起**。

这个启动器把它变成：

```
双击 .app  →  原生窗口弹出 WebUI  →  关窗，服务自动停干净
```

三个实现要点：

| 问题 | 处理方式 |
| --- | --- |
| 端口冲突 | 每次启动向内核要一个**随机空闲端口**，不会撞 8080/5173 |
| 关窗后进程残留 | uvicorn 用 `start_new_session=True` 独占进程组，关窗时 `killpg` **整组回收**，连爬虫派生的子进程一起清 |
| 强制退出后残留孤儿 | 启动时把子进程 pid + 端口记到 `~/.config/mediacrawler-launcher/uvicorn.pid`，下次启动先做一次残留清理 |
| 双击启动报 `uv command not found` | 双击 `.app` 时系统只给极简 PATH（没有 `~/.local/bin`、没有 Homebrew）。生成 `.app` 时把 `uv` 所在目录**烘焙进启动脚本**，后端继承到正确 PATH |
| 窗口关不掉（`Cmd+Q` 无效） | 提供 `--stop`：先停后端再关窗口，一条命令收干净 |

那句 `uv command not found` 是真踩过的坑：MediaCrawler 的后端会以命令名 `uv` 去拉起爬虫
（`api/services/crawler_manager.py`），所以在 Finder 里双击启动时，即使终端里 `uv` 用得好好的，
WebUI 的「环境检测」仍会报 `[错误] uv command not found`。

---

## 系统要求

- macOS 12 或更高（Apple Silicon / Intel 都行）
- [uv](https://docs.astral.sh/uv/) — `brew install uv`
- Node.js 18+（只在安装时构建前端用）— `brew install node`
- Google Chrome — MediaCrawler 依赖浏览器登录态，建议装

---

## 安装

```bash
git clone https://github.com/JohnWelo/mediacrawler-macos-launcher.git
cd mediacrawler-macos-launcher
chmod +x install.sh build_app.sh uninstall.sh
./install.sh
```

脚本会依次做五件事：

1. 检查 `uv` / Node.js / Chrome
2. 从**官方仓库**拉取 MediaCrawler 到 `~/MediaCrawler`（不打包、不镜像上游源码）
3. `uv sync` 装 Python 依赖，再把 `pywebview` 装进同一个 venv
4. `cd webui && npm install && npm run build` 构建前端到 `api/webui/`
5. 生成 `~/Applications/MediaCrawler WebUI.app`

装到别的位置：

```bash
./install.sh --dir ~/code/MediaCrawler
```

已经有 MediaCrawler 了，跳过拉取：

```bash
./install.sh --skip-clone --dir ~/Desktop/AGI/media-crawler
```

---

## 使用

双击 **`~/Applications/MediaCrawler WebUI.app`**。

首次打开会做环境检测，通过后点「开始使用」即可。爬取前记得在
`config/base_config.py` 改 `KEYWORDS`，并在 WebUI 里选登录方式（扫码 / Cookie / 手机号）。

想从命令行跑：

```bash
cd ~/MediaCrawler
.venv/bin/python ~/.local/share/mediacrawler-launcher/webui_native.py
```

自检（不弹窗，只报告环境是否就绪）：

```bash
cd ~/MediaCrawler
.venv/bin/python ~/.local/share/mediacrawler-launcher/webui_native.py --check
```

停掉正在运行的实例（后端和窗口一起关）：

```bash
cd ~/MediaCrawler
.venv/bin/python ~/.local/share/mediacrawler-launcher/webui_native.py --stop
```

换一个应用名或输出目录：

```bash
./build_app.sh --project ~/MediaCrawler --name "MC 抓取器" --out /Applications
```

---

## 卸载

```bash
./uninstall.sh              # 只删启动器和 .app，源码目录不动
./uninstall.sh --purge ~/MediaCrawler   # 连源码一起删，需二次确认
```

产物都落在这些位置，手动删也一样：

| 路径 | 内容 |
| --- | --- |
| `~/Applications/MediaCrawler WebUI.app` | 双击入口 |
| `~/.local/share/mediacrawler-launcher/` | 启动器脚本 |
| `~/.config/mediacrawler-launcher/` | 配置（项目路径）与运行日志 |

---

## 常见问题

**WebUI 报 `uv command not found`**
说明 `.app` 里的 PATH 没带上 `uv`。重跑 `./build_app.sh` 会重新烘焙路径。
如果你把 `uv` 装在非标准位置，先 `export PATH="你的uv目录:$PATH"` 再构建。

**窗口一片空白 / 一直转圈**
后端没起来。看日志：

```bash
tail -50 ~/.config/mediacrawler-launcher/launcher.log
```

最常见的原因是 `api/webui/index.html` 不存在——前端没构建。在项目里跑：

```bash
cd ~/MediaCrawler/webui && npm install && npm run build
```

**扫码登录后窗口关了就丢了登录态**
不会丢。登录态存在 Chrome 用户数据目录里，跟这个启动器无关。启动器每次只是新起一个后端进程。

**关窗后还有进程**
正常关窗（点红点或 `Cmd+W`）时整组 `killpg`，不会残留。
如果是强制结束、崩溃或 `kill -9`，后端会变成孤儿——但下次启动时会自动清掉，也可以手动：

```bash
cd ~/MediaCrawler
.venv/bin/python ~/.local/share/mediacrawler-launcher/webui_native.py --stop
```

**`Cmd+Q` 关不掉窗口**
pywebview 应用对 AppleScript 的 `quit` 事件响应不可靠（实测会报 `-10004 权限违例`），
用窗口的红色关闭按钮即可；想彻底关干净就用上面的 `--stop`。

**想改成浏览器打开而不是原生窗口**
`launcher/webui_native.py` 里有 `webview.create_window(...)`，替换成 `webbrowser.open(url)` 即可，其余逻辑不用动。

---

## 致谢

**这个项目的全部核心能力都来自 [NanmiCoder](https://github.com/NanmiCoder) 的 [MediaCrawler](https://github.com/NanmiCoder/MediaCrawler)。**

它用 Playwright 驱动真实浏览器，绕开了一堆平台的前端加密逆向，把小红书、抖音、快手、B站、微博、贴吧、知乎的
公开内容采集整合成一套统一接口，还自带 WebUI 和多种存储后端（CSV / JSON / SQLite / MySQL / PostgreSQL / MongoDB）。
这是个工程量很大的项目，本仓库只是给它补了一个 macOS 的「双击启动」外壳。

原项目文档：[README](https://github.com/NanmiCoder/MediaCrawler/blob/main/README.md) ·
[在线文档](https://nanmicoder.github.io/MediaCrawler/) ·
[免责声明](https://github.com/NanmiCoder/MediaCrawler#disclaimer)

也感谢 [pywebview](https://pywebview.flowrl.com/) 提供轻量的原生窗口封装。

---

## 许可证

本仓库自己的代码（`launcher/`、`*.sh`）以 **MIT** 发布，见 [LICENSE](LICENSE)。

**这个许可证不覆盖 MediaCrawler。** 上游采用
[NON-COMMERCIAL LEARNING LICENSE 1.1](https://github.com/NanmiCoder/MediaCrawler/blob/main/LICENSE)：
仅授权非商业学习用途、不可转让、要求保留版权声明。本仓库因此**不包含也不分发**上游源码，
只通过脚本让用户从官方仓库自行获取。详见 [NOTICE.md](NOTICE.md)。

---

## 免责声明

本项目仅用于技术学习与研究。使用者应自行遵守目标平台的用户协议、`robots.txt` 与相关法律法规，
不得用于商业用途、大规模抓取或任何干扰平台正常运营的行为。因使用产生的任何后果由使用者自行承担。
