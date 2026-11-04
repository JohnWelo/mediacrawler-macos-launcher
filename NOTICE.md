# NOTICE / 声明

## 本仓库包含什么

只有四类文件，全部为本仓库自行编写：

| 文件 | 作用 |
| --- | --- |
| `launcher/webui_native.py` | 原生窗口启动器（起 uvicorn、开窗口、关窗回收进程） |
| `install.sh` | 依赖检查、拉取上游、构建、生成 `.app` |
| `build_app.sh` | 从已装好的项目生成 `.app` 包 |
| `uninstall.sh` | 清理启动器与 `.app` |
| `README.md` / `LICENSE` / 本文件 | 文档 |

## 本仓库**不**包含什么

**不包含 MediaCrawler 的任何源码、文档、图片、字体或前端构建产物。**

`install.sh` 运行时通过 `git clone` 从官方仓库
<https://github.com/NanmiCoder/MediaCrawler> 拉取源码到用户自己的磁盘。
本仓库本身不镜像、不打包、不再分发上游代码。

## 上游许可证

MediaCrawler 采用 **NON-COMMERCIAL LEARNING LICENSE 1.1**，
Copyright (c) 2024 relakkes@gmail.com。

其授权范围为「use, copy, modify, and merge」，限定**非商业学习用途**，且明确标注 **non-transferable**；
条款要求在所有副本的显著位置保留版权声明与许可声明；商业用途或对第三方施加不当影响需取得作者书面同意。

因此：

- 你**可以**用这个启动器自由地在本机使用、修改 MediaCrawler 用于学习研究
- 你**不可以**将 MediaCrawler 用于商业用途
- 若你要再分发 MediaCrawler，请自行阅读并遵守上游许可证，并保留其版权与许可声明

许可证全文：<https://github.com/NanmiCoder/MediaCrawler/blob/main/LICENSE>

## 为什么不直接把上游源码一起打包

因为上游许可证只授予使用/复制/修改/合并，**未授予公开再分发（publish / distribute）的权利**。
把上游源码整体打包上传到另一个公开仓库，会超出许可范围。
本仓库因此选择「脚本拉取」而不是「源码镜像」——用户拿到的永远是官方版本，也能直接用上游的更新。

## 名字与商标

「MediaCrawler」是上游项目的名称。本仓库是第三方配套工具，**非官方**，与 NanmiCoder 无从属关系，
也未获得其背书。命名中沿用该词仅为准确说明用途。

## 免责

本工具仅供技术学习与研究。使用 MediaCrawler 采集数据时，请自行遵守目标平台的用户协议、`robots.txt`
与所在地法律法规，不得进行大规模抓取或干扰平台正常运营。使用产生的后果由使用者自行承担。
