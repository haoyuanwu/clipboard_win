#requires -Version 7.0
param(
  [ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
  [switch]$SkipBuild,
  [switch]$SkipChecks,
  [string]$IsccPath
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts/release-common.ps1')
if (-not $Version) { $Version = Get-ReleaseVersion $PSScriptRoot }
if ($Version -ne (Get-ReleaseVersion $PSScriptRoot)) { throw '发布版本必须与 pubspec.yaml 一致。' }
if (-not $IsccPath) {
  $iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
  if ($iscc) { $IsccPath = $iscc.Source }
  else {
    $candidates = @("$env:ProgramFiles/Inno Setup 7/ISCC.exe", "${env:ProgramFiles(x86)}/Inno Setup 6/ISCC.exe", "$env:LOCALAPPDATA/Programs/Inno Setup 6/ISCC.exe")
    $IsccPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  }
}
if (-not $IsccPath -or -not (Test-Path -LiteralPath $IsccPath)) { throw '需要 Inno Setup 6.4 或更高版本。安装后重试，或使用 -IsccPath 指定 ISCC.exe。' }
Push-Location $PSScriptRoot
try {
  $runner = Get-FlutterRunner
  if (-not $SkipChecks) {
    Invoke-FlutterRelease $runner @('analyze','lib','test')
    Invoke-FlutterRelease $runner @('test')
  }
  if (-not $SkipBuild) { Invoke-FlutterRelease $runner @('build','windows','--release','--no-tree-shake-icons',"--dart-define=APP_VERSION=$Version") }
  # Release icon subsetting can omit Cupertino glyphs referenced through shared controls.
  # Ship full fonts on desktop, and verify the packaged font matches its source.
  $config = Get-Content -LiteralPath (Join-Path $PSScriptRoot '.dart_tool/package_config.json') -Raw | ConvertFrom-Json
  $iconsPackage = $config.packages | Where-Object name -eq 'cupertino_icons'
  $packageUri = [Uri]::new([Uri]::new((Join-Path $PSScriptRoot '.dart_tool/package_config.json')), [string]$iconsPackage.rootUri)
  $sourceFont = Join-Path $packageUri.LocalPath 'assets/CupertinoIcons.ttf'
  $builtFont = Join-Path $PSScriptRoot 'build/windows/x64/runner/Release/data/flutter_assets/packages/cupertino_icons/assets/CupertinoIcons.ttf'
  if ((Get-FileHash -LiteralPath $sourceFont).Hash -ne (Get-FileHash -LiteralPath $builtFont).Hash) { throw '发布字体不完整，请使用当前脚本重新构建，勿复用旧的裁剪图标构建。' }
  if (-not $SkipChecks) { & (Join-Path $PSScriptRoot 'scripts/test-native.ps1') }
  $packageName = "PocketCube-Windows-x64-v$Version"
  & (Join-Path $PSScriptRoot 'package.ps1') -SkipBuild -PackageName $packageName
  if (-not $?) { throw '免安装包生成失败。' }
  $packagePath = Join-Path $PSScriptRoot "dist/$packageName"
  Invoke-ReleaseCommand $IsccPath @("/DAppVersion=$Version", "/DPackageDir=$packagePath", (Join-Path $PSScriptRoot 'packaging/windows-installer.iss'))
  $hashPaths = @((Join-Path $PSScriptRoot "dist/PocketCube-$Version-windows-x64-setup.exe"), (Join-Path $PSScriptRoot "dist/$packageName.zip"))
  $hashLines = foreach ($hashPath in $hashPaths) { $hash = Get-FileHash -LiteralPath $hashPath -Algorithm SHA256; "$($hash.Hash)  $([IO.Path]::GetFileName($hashPath))" }
  $hashLines | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'dist/SHA256SUMS.txt') -Encoding ascii
  Get-Item -LiteralPath $hashPaths | Select-Object FullName,Length
} finally { Pop-Location }
