# Windows 验证记录

验证日期：2026-10-23（Asia/Hong_Kong）。

- Flutter：3.47.7 / Dart 3.13.5。
- Windows 11 x64 / Visual Studio 2026，Release 构建成功。
- `dart analyze lib test`：无问题。
- `flutter test`：17 项通过。
- 实际 Windows 剪贴板：Unicode 文字、重复合并、RTF、文件列表和 DIB 图片捕获通过。
- 最终运行包：主窗口、托盘弹窗与置顶中转站能够显示；托盘单击复制实际写回系统剪贴板，复制次数只增加一次。
- 辅助引擎首次启动的通道注册时序已修复，并加入握手回归测试。
- 多文件以整组文件夹拖回的去重规则已加入回归测试。
- 视觉对齐检查：主窗口 440×640、托盘 390×520、中转站 350×520；整合标题栏与红黄绿按钮；首张卡片 (16,104)、宽 408；设置 390×440、详情 420×420、退出确认宽 310；420 宽的浅/深色与中转站 320×360 最小尺寸无溢出。
- 最终发布包窗口按钮：关闭后隐藏、最小化、还原均正常；缩放后宽度限制为 460。首次启动的自动点击早于界面就绪，待界面就绪后重试通过。
- 最新磨砂版本：托盘、中转、设置、详情、关于、退出面板共用半透明模糊表面，模糊 sigma 28。桌面窗口请求 Acrylic，不再回退为清晰透明；当前系统 EnableTransparency=0，实际验证为较实的系统材质回退，未在系统透明开启状态下验证桌面模糊。
- Windows 11 托盘首次可见偏好：实际演示程序的 IsPromoted=1、SuperClipboardDefaultVisible=1 已确认；后续运行保留手动显示选择。此兼容处理受 Windows 版本和任务栏策略影响。
- 发现用户已运行旧版后，最终检查改为专用 --preview-instance（必须同时使用独立目录、--no-capture、--no-startup），窗口脚本按进程 ID 定位，避免命中用户实例。
- 本轮界面预览使用 `--no-capture --no-startup` 与独立示例存档，不采集个人剪贴板，也不修改开机启动。
- 检查截图：`screenshots/windows-main.png`、`screenshots/windows-popover.png`、`screenshots/windows-transfer.png`、`screenshots/transfer-frosted.png`；主题布局截图见 `main-light.png`、`main-dark.png` 和 `settings-dark.png`。

Windows 剪贴板验证脚本会临时替换系统剪贴板。早期验证遇到恢复失败；后续脚本已改为预先读取独立快照并重试恢复，最终回写验证已恢复测试前快照。早期被替换的原内容不保证已恢复。

尚未全面人工验证：向任意第三方软件的 OLE 拖放、所有视频格式、任务管理器额外禁用的开机启动状态、复杂 RTF 文档的完整排版。

平台差异与具体支持范围见 `PORTING.md`。
