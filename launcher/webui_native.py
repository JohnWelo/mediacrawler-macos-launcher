#!/usr/bin/env python3
"""MediaCrawler WebUI —— macOS 原生窗口启动器。

把 MediaCrawler 的 WebUI 装进一个系统原生窗口，双击即用：

    ［双击 .app］ → 随机空闲端口起 uvicorn → pywebview 弹出原生窗口
                  → 关窗即按进程组终止服务，不留残余进程

本文件**不含 MediaCrawler 的任何源码**，只是调用你本机已安装的那份。
上游项目：https://github.com/NanmiCoder/MediaCrawler

用法::

    python3 webui_native.py                 启动原生窗口
    python3 webui_native.py --check         只做环境自检，不弹窗
    python3 webui_native.py --project PATH  手动指定 MediaCrawler 目录
    python3 webui_native.py --list          打印探测到的项目路径后退出
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

WINDOW_TITLE = "MediaCrawler WebUI"
WINDOW_SIZE = (1280, 860)
WINDOW_MIN_SIZE = (1024, 700)
READY_TIMEOUT = 45.0

CONFIG_DIR = Path.home() / ".config" / "mediacrawler-launcher"
CONFIG_FILE = CONFIG_DIR / "config.json"
LOG_FILE = CONFIG_DIR / "launcher.log"
PID_FILE = CONFIG_DIR / "uvicorn.pid"


# --------------------------------------------------------------------------- #
# 基础设施
# --------------------------------------------------------------------------- #
def log(message: str) -> None:
    """写入日志。放在 ~/.config 而不是项目目录，避免污染上游源码树。"""
    try:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        with LOG_FILE.open("a", encoding="utf-8") as handle:
            stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            handle.write(f"[{stamp}] {message}\n")
    except OSError:
        pass  # 日志失败不影响主流程


def alert(message: str, title: str = WINDOW_TITLE) -> None:
    """弹系统对话框。双击 .app 启动时没有终端可看，只能靠弹窗报错。"""
    log(f"ALERT: {message}")
    if sys.platform != "darwin":
        print(f"[错误] {message}", file=sys.stderr)
        return
    safe = message.replace("\\", "\\\\").replace('"', "'").replace("\n", " ")
    subprocess.run(
        ["osascript", "-e", f'display alert "{title}" message "{safe}" as critical'],
        capture_output=True,
    )


def free_port() -> int:
    """向内核要一个当前空闲的端口。"""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def wait_until_ready(url: str, timeout: float = READY_TIMEOUT) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=2) as response:
                if response.status == 200:
                    return True
        except Exception:
            pass
        time.sleep(0.3)
    return False


# --------------------------------------------------------------------------- #
# 进程回收
#
# 正常关窗时 webview.start() 返回，finally 会整组回收 uvicorn。
# 但「强制退出 / 崩溃 / 被 kill -9」时 finally 跑不到，uvicorn 就变成孤儿。
# 所以额外用 pid 文件记录子进程，下次启动先清理一次。
# --------------------------------------------------------------------------- #
def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True  # 存在但无权限，视为活着


def _read_pid() -> dict | None:
    """读取记录的运行信息。兼容早期只写了一个数字的格式。"""
    try:
        raw = PID_FILE.read_text(encoding="utf-8").strip()
    except OSError:
        return None
    try:
        data = json.loads(raw)
        if isinstance(data, dict) and "pid" in data:
            return {"pid": int(data["pid"]), "port": int(data.get("port") or 0)}
    except (ValueError, TypeError):
        pass
    try:
        return {"pid": int(raw), "port": 0}
    except ValueError:
        return None


def _write_pid(pid: int, port: int = 0) -> None:
    try:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        PID_FILE.write_text(
            json.dumps({"pid": pid, "port": port}), encoding="utf-8"
        )
    except OSError as exc:
        log(f"WARN: 无法写入 pid 文件: {exc}")


def _clear_pid() -> None:
    try:
        PID_FILE.unlink(missing_ok=True)
    except OSError:
        pass


def _port_listening(port: int) -> bool:
    if not port:
        return False
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.5)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def _is_our_uvicorn(pid: int, port: int) -> bool:
    """判断这个 pid 是不是我们起的 uvicorn，防止 pid 复用误杀。"""
    # 首选：命令行匹配
    try:
        cmdline = subprocess.run(
            ["ps", "-o", "command=", "-p", str(pid)],
            capture_output=True, text=True, timeout=5,
        ).stdout
        if cmdline.strip():
            return "uvicorn" in cmdline and "api.main:app" in cmdline
    except (OSError, subprocess.SubprocessError):
        pass  # ps 不可用（某些受限环境会直接拒绝），走兜底

    # 兜底：记录的端口仍在监听，基本可以确定是我们的后端
    return _port_listening(port)


def _terminate(process: subprocess.Popen) -> None:
    """按进程组终止，连带清掉爬虫派生的子进程。"""
    try:
        os.killpg(os.getpgid(process.pid), signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        return
    try:
        process.wait(timeout=5)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(os.getpgid(process.pid), signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass


def _kill_pid_group(pid: int) -> None:
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(os.getpgid(pid), sig)
        except (ProcessLookupError, PermissionError):
            return
        for _ in range(30):
            if not _pid_alive(pid):
                return
            time.sleep(0.1)


def reap_stale() -> bool:
    """清掉上一次异常退出遗留的 uvicorn。返回是否清掉了什么。"""
    info = _read_pid()
    if info is None:
        return False
    pid, port = info["pid"], info["port"]

    if not _pid_alive(pid):
        _clear_pid()
        return False

    if not _is_our_uvicorn(pid, port):
        _clear_pid()
        return False

    log(f"检测到上次残留的 uvicorn (pid={pid}, port={port})，正在清理")
    _kill_pid_group(pid)
    _clear_pid()
    return True


# --------------------------------------------------------------------------- #
# 定位 MediaCrawler
# --------------------------------------------------------------------------- #
def looks_like_project(path: Path) -> bool:
    """靠两个标志文件判断是不是 MediaCrawler 根目录。"""
    return (path / "main.py").is_file() and (path / "api" / "main.py").is_file()


def project_candidates() -> list[Path]:
    """按优先级列出候选目录。"""
    found: list[Path] = []

    env_home = os.environ.get("MEDIACRAWLER_HOME")
    if env_home:
        found.append(Path(env_home).expanduser())

    try:
        data = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
        configured = data.get("project")
        if configured:
            found.append(Path(configured).expanduser())
    except (OSError, ValueError):
        pass

    here = Path(__file__).resolve().parent
    found.extend([here, here.parent, here.parent.parent])

    home = Path.home()
    found.extend(
        [
            home / "MediaCrawler",
            home / "Documents" / "MediaCrawler",
            home / "Desktop" / "MediaCrawler",
            home / "Projects" / "MediaCrawler",
            home / ".local" / "share" / "MediaCrawler",
        ]
    )
    return found


def resolve_project(cli_value: str | None) -> Path | None:
    if cli_value:
        candidate = Path(cli_value).expanduser().resolve()
        if looks_like_project(candidate):
            return candidate
        alert(f"指定目录不是 MediaCrawler 项目（缺少 main.py 与 api/main.py）：\n{candidate}")
        return None

    for candidate in project_candidates():
        try:
            resolved = candidate.expanduser().resolve()
        except OSError:
            continue
        if looks_like_project(resolved):
            return resolved
    return None


def save_project(path: Path) -> None:
    """把项目路径记下来，下次双击 .app 就不用再探测。"""
    try:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        CONFIG_FILE.write_text(
            json.dumps({"project": str(path)}, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    except OSError as exc:
        log(f"WARN: 无法写入配置 {CONFIG_FILE}: {exc}")


# --------------------------------------------------------------------------- #
# 自检
# --------------------------------------------------------------------------- #
def check(project: Path | None) -> int:
    problems: list[str] = []

    if project is None:
        print("FAIL: 没有找到 MediaCrawler 目录")
        print("      请先运行 install.sh，或用 --project 指定路径")
        return 1

    venv_python = project / ".venv" / "bin" / "python"
    webui_index = project / "api" / "webui" / "index.html"

    # pywebview 装在项目 venv 里，不在系统 python 里。
    # 如果用户用系统 python3 跑 --check，会误报「缺少 pywebview」——
    # 这里自动切到项目 venv 的 python 重跑一次。
    if venv_python.exists():
        try:
            already_venv = Path(sys.executable).resolve() == venv_python.resolve()
        except OSError:
            already_venv = False
        if not already_venv:
            return subprocess.run(
                [
                    str(venv_python),
                    str(Path(__file__).resolve()),
                    "--check",
                    "--project",
                    str(project),
                ]
            ).returncode

    if not venv_python.exists():
        problems.append(f"缺少虚拟环境：{venv_python}（在项目目录执行 uv sync）")
    if not webui_index.exists():
        problems.append(
            f"缺少前端构建产物：{webui_index}（在 webui/ 执行 npm install && npm run build）"
        )

    try:
        import webview  # noqa: F401

        try:
            from importlib.metadata import version as _pkg_version

            webview_version = _pkg_version("pywebview")
        except Exception:
            webview_version = getattr(webview, "__version__", "unknown")
    except ImportError:
        problems.append("缺少 pywebview（uv pip install --python .venv/bin/python pywebview）")
        webview_version = "-"

    if shutil.which("uv") is None:
        problems.append("PATH 中没有 uv —— WebUI 的「环境检测」会报 uv command not found")

    if problems:
        for item in problems:
            print(f"FAIL: {item}")
        return 1

    print(f"OK: project   = {project}")
    print(f"OK: venv      = {venv_python}")
    print(f"OK: pywebview = {webview_version}")
    print(f"OK: webui     = {webui_index}")
    print(f"OK: uv        = {shutil.which('uv')}")
    return 0


# --------------------------------------------------------------------------- #
# 主流程
# --------------------------------------------------------------------------- #
def run(project: Path) -> int:
    try:
        import webview
    except ImportError:
        alert(
            "缺少 pywebview，原生窗口无法创建。\n\n"
            "请在项目目录执行：\n"
            "uv pip install --python .venv/bin/python pywebview"
        )
        return 1

    venv_python = project / ".venv" / "bin" / "python"
    if not venv_python.exists():
        alert(f"找不到项目虚拟环境：\n{venv_python}\n\n请在项目目录执行 uv sync")
        return 1

    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    save_project(project)

    if reap_stale():
        print("已清理上次残留的后端进程", file=sys.stderr)

    port = free_port()
    url = f"http://127.0.0.1:{port}"
    log(f"启动 uvicorn: {url} (project={project})")

    # uvicorn 作为子进程独占一个进程组，关窗时整组回收
    with LOG_FILE.open("a", encoding="utf-8") as log_handle:
        process = subprocess.Popen(
            [
                str(venv_python), "-m", "uvicorn", "api.main:app",
                "--host", "127.0.0.1",
                "--port", str(port),
                "--log-level", "warning",
            ],
            cwd=str(project),
            env=os.environ.copy(),
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    _write_pid(process.pid, port)

    if not wait_until_ready(url):
        _terminate(process)
        _clear_pid()
        alert(f"后端启动超时（端口 {port}）。\n\n日志：{LOG_FILE}")
        return 1

    log(f"uvicorn 就绪，创建原生窗口: {url}")
    webview.create_window(
        WINDOW_TITLE,
        url=url,
        width=WINDOW_SIZE[0],
        height=WINDOW_SIZE[1],
        min_size=WINDOW_MIN_SIZE,
    )
    try:
        webview.start()
    finally:
        log("窗口已关闭，停止 uvicorn")
        _terminate(process)
        _clear_pid()
        log("已结束")
    return 0


def _stop_windows() -> int:
    """关掉正在显示的窗口进程（排除自己）。返回关掉几个。"""
    try:
        output = subprocess.run(
            ["pgrep", "-f", "webui_native.py"],
            capture_output=True, text=True, timeout=5,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return 0

    me = os.getpid()
    count = 0
    for token in output.split():
        try:
            pid = int(token)
        except ValueError:
            continue
        if pid == me:
            continue
        try:
            os.kill(pid, signal.SIGTERM)
            count += 1
        except (ProcessLookupError, PermissionError):
            pass
    return count


def stop_running() -> int:
    """停掉正在运行的实例（--stop）：先停后端，再关窗口。"""
    stopped: list[str] = []

    info = _read_pid()
    if info is not None and _pid_alive(info["pid"]):
        _kill_pid_group(info["pid"])
        stopped.append(f"后端 pid={info['pid']}")
        log(f"--stop: 已停止 pid={info['pid']}")
    _clear_pid()

    if not stopped:
        # pid 文件缺失或已失效时兜底扫一遍
        result = subprocess.run(
            ["pkill", "-f", "uvicorn api.main:app"], capture_output=True
        )
        if result.returncode == 0:
            stopped.append("后端（按命令行匹配）")

    windows = _stop_windows()
    if windows:
        stopped.append(f"{windows} 个窗口")

    if stopped:
        print("已停止：" + "、".join(stopped))
    else:
        print("当前没有在运行的实例")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="MediaCrawler WebUI 原生窗口启动器",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--check", action="store_true", help="只做环境自检，不弹窗")
    parser.add_argument("--list", action="store_true", help="打印探测到的项目路径后退出")
    parser.add_argument("--stop", action="store_true", help="停掉正在运行的实例")
    parser.add_argument("--project", metavar="PATH", help="手动指定 MediaCrawler 目录")
    args = parser.parse_args()

    if args.stop:
        return stop_running()

    project = resolve_project(args.project)

    if args.list:
        if project is None:
            print("未找到 MediaCrawler 目录")
            return 1
        print(project)
        return 0

    if args.check:
        return check(project)

    if project is None:
        alert(
            "没有找到 MediaCrawler 项目目录。\n\n"
            "请先运行仓库里的 install.sh 完成安装，\n"
            "或用 --project 参数指定目录。"
        )
        return 1

    return run(project)


if __name__ == "__main__":
    sys.exit(main())
