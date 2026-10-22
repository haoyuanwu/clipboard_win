# GitHub 发布流程

## 首次准备

- 当前目录必须是独立 Git 仓库，默认分支为 main；不能从上级 CleanWin 仓库发布。
- 安装 PowerShell 7+、Flutter Windows 工具链、Visual Studio C++ 桌面组件、Git、GitHub CLI 与 Inno Setup 6.4+。
- 使用 `gh auth login` 登录。凭据由 GitHub CLI 安全存储；脚本不包含令牌。不把令牌填入仓库 URL。
- 账户需要目标仓库的写入与发布权限；第一次创建仓库还需要创建仓库权限。

第一次创建并公开发布：

```powershell
.\publish.ps1 -CreateRepository -CommitMessage "首次发布 Windows 版：实现剪贴板历史、记事本、中转站和磨砂界面"
```

## 下次发布

1. 更新 pubspec.yaml 中的版本，如 `1.2.1+2`。
2. 更新 CHANGELOG.md，添加 `docs/release-notes/v1.2.1.md`。
3. 在 main 分支运行 ` .\publish.ps1 -CommitMessage "发布 1.2.1：优化搜索与窗口交互"`。

默认版本从 pubspec.yaml 读取。需要检查发布计划时使用 ` .\publish.ps1 -Plan`，不会执行构建、推送或发布。

## 脚本行为

发布前检查独立仓库、当前分支、中文版本说明、登录与疑似敏感内容；自动执行静态检查和测试。随后构建 Release、生成按版本命名的免安装 ZIP、编译中文安装程序，生成两个附件的 SHA-256 校验值。

源码以中文提交推送到 main，并创建带中文注释的版本标签。先创建草稿 Release，再上传三个附件，确认文件名和字节数一致后正式发布。不会强制推送，不移动已有标签，不覆盖正式发布的同版本。

网络中断时，如该版本仍为草稿且标签对应当前提交，可直接重跑脚本。已正式发布的版本需要提升版本号后发布。

`-SkipBuild` 仅跳过 Flutter 编译，仍检查、重新打包和编译安装程序，适合确认现有 Release 构建与源码一致时使用。`build-release.ps1 -SkipBuild -SkipChecks` 仅用于已完成验证的本地重新打包。

## 安装程序

`packaging/windows-installer.iss` 为 Inno Setup 源文件。默认按当前用户安装，不请求管理员权限，可选桌面快捷方式。卸载保留 `%APPDATA%\SuperClipboard` 中的个人历史。安装前会检查正在运行的程序，需从托盘退出旧版。

当前没有配置商业代码签名。若以后添加签名，证书与口令只保存在本机安全位置，不放进仓库。
