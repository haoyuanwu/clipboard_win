#requires -Version 7.0
param(
  [string]$Repository = 'haoyuanwu/SuperClipboard-Windows',
  [ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
  [string]$CommitMessage,
  [string]$NotesFile,
  [switch]$CreateRepository,
  [switch]$SkipBuild,
  [switch]$Plan
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'scripts/release-common.ps1')
$project = $PSScriptRoot
if (-not $Version) { $Version = Get-ReleaseVersion $project }
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw '仓库名称格式应为 用户名/仓库名。' }
if (-not $CommitMessage) { $CommitMessage = "发布 Windows v${Version}：更新功能、界面与运行包" }
if (-not $NotesFile) { $NotesFile = Join-Path $project "docs/release-notes/v$Version.md" }
if (-not (Test-Path -LiteralPath $NotesFile)) { throw "缺少中文版本说明：$NotesFile" }
$NotesFile = (Resolve-Path -LiteralPath $NotesFile).Path
$packageName = "SuperClipboard-Windows-x64-v$Version"
$installerName = "SuperClipboard-$Version-windows-x64-setup.exe"
$remoteUrl = "https://github.com/$Repository.git"
if ($Plan) {
  Write-Output "目标公开仓库：https://github.com/$Repository"
  Write-Output "版本：v$Version；中文提交：$CommitMessage"
  Write-Output '执行流程：凭据与敏感内容检查 → 静态检查/测试 → 构建/打包/安装程序 → 提交/推送 → 草稿发布 → 上传并核验 → 正式发布。'
  Write-Output "发布附件：$installerName、$packageName.zip、SHA256SUMS.txt"
  Write-Output '凭据仅来自 GitHub CLI 安全登录或当前进程 GH_TOKEN，不写入脚本或仓库。'
  return
}
Push-Location $project
try {
  $repoRoot = (& git rev-parse --show-toplevel 2>$null)
  if ($LASTEXITCODE -ne 0 -or [IO.Path]::GetFullPath($repoRoot).TrimEnd('\','/') -ne $project.TrimEnd('\','/')) {
    throw '请在本项目独立 Git 仓库中运行，禁止将上级或其他项目一并推送。'
  }
  $branch = (& git branch --show-current).Trim()
  if ($branch -ne 'main') { throw '发布脚本要求在 main 分支执行，请先完成分支合并。' }
  Invoke-ReleaseCommand gh @('api','user','--jq','.login')
  $existingRelease = & gh release view "v$Version" --repo $Repository --json isDraft,tagName 2>$null
  if ($LASTEXITCODE -eq 0 -and -not (($existingRelease | ConvertFrom-Json).isDraft)) {
    throw "v$Version 已正式发布，请更新 pubspec.yaml 版本并添加对应中文版本说明。"
  }
  $files = & git ls-files --cached --others --exclude-standard
  if ($LASTEXITCODE -ne 0) { throw '读取待发布文件失败。' }
  foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
    if ([IO.Path]::GetExtension($file) -match '^\.(png|jpg|jpeg|ico|gif|webp|ttf|otf|zip|exe|dll)$') { continue }
    if ((Get-Item -LiteralPath $file).Length -gt 4MB) { throw "请检查不应进入源码的大文件：$file" }
    $content = [IO.File]::ReadAllText((Join-Path $project $file))
    if ($content -match 'github_pat_[A-Za-z0-9_]{25,}|gh[pousr]_[A-Za-z0-9]{20,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----') {
      throw "发现疑似凭据，发布已停止。请检查文件：$file"
    }
  }
  & (Join-Path $project 'build-release.ps1') -Version $Version -SkipBuild:$SkipBuild
  if (-not $?) { throw '构建发布包失败。' }
  $assets = @((Join-Path $project "dist/$installerName"), (Join-Path $project "dist/$packageName.zip"), (Join-Path $project 'dist/SHA256SUMS.txt'))
  foreach ($asset in $assets) { if (-not (Test-Path -LiteralPath $asset -PathType Leaf)) { throw "发布附件缺失：$asset" } }
  & gh repo view $Repository --json nameWithOwner --jq .nameWithOwner 2>$null
  if ($LASTEXITCODE -ne 0) {
    if (-not $CreateRepository) { throw '无法访问目标仓库。首次创建时添加 -CreateRepository；也请检查网络和登录权限。' }
    Invoke-ReleaseCommand gh @('repo','create',$Repository,'--public','--description','SuperClipboard Windows 版｜Flutter 剪贴板历史、独立记事本与悬浮中转站，支持半透明磨砂界面')
  }
  $origin = & git remote get-url origin 2>$null
  if ($LASTEXITCODE -ne 0) { Invoke-ReleaseCommand git @('remote','add','origin',$remoteUrl) }
  elseif ($origin.Trim() -notin @($remoteUrl,"https://github.com/$Repository","git@github.com:$Repository.git")) {
    throw 'origin 与目标仓库不一致，已停止，防止误推送。'
  }
  Invoke-ReleaseCommand git @('add','--all','--','.')
  Invoke-ReleaseCommand git @('diff','--cached','--check')
  & git diff --cached --quiet
  if ($LASTEXITCODE -eq 1) { Invoke-ReleaseCommand git @('commit','-m',$CommitMessage) }
  elseif ($LASTEXITCODE -ne 0) { throw '读取暂存区失败。' }
  $head = (& git rev-parse HEAD).Trim()
  $tagHead = & git rev-parse "refs/tags/v$Version`^{}" 2>$null
  if ($LASTEXITCODE -eq 0) {
    if ($tagHead.Trim() -ne $head) { throw '版本标签已指向其他提交，禁止移动或覆盖已有版本。' }
  } else { Invoke-ReleaseCommand git @('tag','-a',"v$Version",'-m',"发布 Windows v$Version") }
  # Use gh's credential helper for this invocation; never persist a token in the remote URL.
  Invoke-ReleaseCommand git @('-c','credential.helper=','-c','credential.helper=!gh auth git-credential','push','-u','origin','main')
  Invoke-ReleaseCommand git @('-c','credential.helper=','-c','credential.helper=!gh auth git-credential','push','origin',"refs/tags/v$Version")
  $draft = & gh release view "v$Version" --repo $Repository --json isDraft 2>$null
  if ($LASTEXITCODE -ne 0) {
    Invoke-ReleaseCommand gh @('release','create',"v$Version",'--repo',$Repository,'--verify-tag','--draft','--title',"SuperClipboard Windows v$Version",'--notes-file',$NotesFile)
  } elseif (-not (($draft | ConvertFrom-Json).isDraft)) { throw '该版本已被发布，停止覆盖附件。' }
  Invoke-ReleaseCommand gh (@('release','upload',"v$Version",'--repo',$Repository,'--clobber') + $assets)
  $uploaded = (& gh release view "v$Version" --repo $Repository --json assets | ConvertFrom-Json).assets
  if ($LASTEXITCODE -ne 0) { throw '读取已上传附件失败。' }
  foreach ($asset in $assets) {
    $local = Get-Item -LiteralPath $asset
    $match = @($uploaded | Where-Object name -eq $local.Name)
    if ($match.Count -ne 1 -or $match[0].size -ne $local.Length) { throw "附件上传不完整：$($local.Name)，版本仍保留为草稿。" }
  }
  Invoke-ReleaseCommand gh @('release','edit',"v$Version",'--repo',$Repository,'--draft=false','--latest')
  Write-Output "源码：https://github.com/$Repository"
  Write-Output "下载：https://github.com/$Repository/releases/tag/v$Version"
} finally { Pop-Location }
