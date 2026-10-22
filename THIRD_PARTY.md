# 第三方组件

应用图标与交互参考来自 https://github.com/haoyuanwu/SuperClipboard 。

Flutter、Dart 和所用 Dart/Flutter 包的授权文本随 Flutter 运行资源提供，位于 data/flutter_assets/NOTICES.Z。

主要组件：

- Flutter / Dart：https://github.com/flutter/flutter
- Cupertino Icons：https://pub.dev/packages/cupertino_icons
- crypto：https://pub.dev/packages/crypto
- Flutter Widget from HTML：https://github.com/daohoangson/flutter_widget_from_html
- media_kit：https://github.com/media-kit/media-kit
- libmpv Windows 构建：https://github.com/media-kit/libmpv-win32-video-build
- libmpv / FFmpeg：https://mpv.io/ 、https://ffmpeg.org/
- ANGLE Windows 构建：https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES
- ANGLE：https://chromium.googlesource.com/angle/angle

视频二进制依赖由 media_kit 的固定版本构建规则下载并校验。相关上游组件各自的许可证以其源项目及构建清单为准。
本机运行包包含 Visual C++ Redistributable 运行库，来源为已安装的 Visual Studio 工具链。

## 固定版本与对应来源

- libmpv 预编译版本：`mpv-dev-x86_64-20230924-git-652a1dd.7z`，由 media_kit_libs_windows_video 1.0.11 的构建文件固定下载并校验。
- 二进制发布页：[libmpv 2023-09-24](https://github.com/media-kit/libmpv-win32-video-build/releases/tag/2023-09-24)。
- mpv 对应源代码：[652a1dd90711839acdccc08004056d25514ef2d8](https://github.com/mpv-player/mpv/tree/652a1dd90711839acdccc08004056d25514ef2d8)。
- Windows 视频依赖构建来源：[media-kit/libmpv-win32-video-build](https://github.com/media-kit/libmpv-win32-video-build)。
- ANGLE 二进制来源：[flutter-windows-ANGLE-OpenGL-ES v1.0.1](https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/tag/v1.0.1)。

`third_party/licenses/` 包含 mpv 固定提交的 Copyright、GPL、LGPL 文本及 media_kit 的 MIT 文本，并复制到运行包的 `licenses/`。mpv 的具体许可取决于上游二进制构建选项，详见所附 Copyright 与对应构建来源。本项目未修改这些视频二进制。
