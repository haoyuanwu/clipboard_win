param([switch]$SkipBuild, [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$PackageName = 'SuperClipboard-Windows-x64')
$ErrorActionPreference = 'Stop'
$packageProject = $PSScriptRoot
$packageBuild = Join-Path $packageProject 'build/windows/x64/runner/Release'
$packageDirectory = Join-Path $packageProject ('dist/'+$PackageName)
if (-not $SkipBuild) {
  . (Join-Path $packageProject 'scripts/release-common.ps1')
  Invoke-FlutterRelease (Get-FlutterRunner) @('build','windows','--release','--no-tree-shake-icons')
}
if (-not (Test-Path -LiteralPath (Join-Path $packageBuild 'clipboard_win.exe'))) {throw 'Build output missing'}
New-Item -ItemType Directory -Force -Path $packageDirectory | Out-Null
Copy-Item -LiteralPath (Join-Path $packageBuild 'clipboard_win.exe') -Destination (Join-Path $packageDirectory 'SuperClipboard.exe') -Force
Get-ChildItem -LiteralPath $packageBuild -Filter '*.dll' | Copy-Item -Destination $packageDirectory -Force
Copy-Item -LiteralPath (Join-Path $packageBuild 'data') -Destination $packageDirectory -Recurse -Force
Copy-Item -LiteralPath (Join-Path $packageProject 'README.md') -Destination $packageDirectory -Force
foreach ($packageDocument in @('PORTING.md','VISUAL_ALIGNMENT.md')) {
  Copy-Item -LiteralPath (Join-Path $packageProject ('docs/'+$packageDocument)) -Destination $packageDirectory -Force
}
Copy-Item -LiteralPath (Join-Path $packageProject 'THIRD_PARTY.md') -Destination $packageDirectory -Force
$packageVswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$packageVs = if (Test-Path -LiteralPath $packageVswhere) { & $packageVswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath }
$packageCrt = if ($packageVs) { Get-ChildItem -Path (Join-Path $packageVs 'VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT') -Directory -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1 }
if (-not $packageCrt) { throw '找不到 Visual C++ 运行库，请安装 Visual Studio C++ 桌面开发组件。' }
if ($packageCrt) {
  foreach ($packageLibrary in @('msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll','concrt140.dll')) {
    Copy-Item -LiteralPath (Join-Path $packageCrt.FullName $packageLibrary) -Destination $packageDirectory -Force
  }
}
$packageAngleRuntime = Join-Path $packageProject 'build/windows/x64/ANGLE/libc++.dll'
if (Test-Path -LiteralPath $packageAngleRuntime) {Copy-Item -LiteralPath $packageAngleRuntime -Destination $packageDirectory -Force}
$packageLicenses = Join-Path $packageProject 'third_party/licenses'
if (Test-Path -LiteralPath $packageLicenses) { Copy-Item -LiteralPath $packageLicenses -Destination $packageDirectory -Recurse -Force }
$packageArchive = Join-Path $packageProject ('dist/'+$PackageName+'.zip')
Compress-Archive -Path $packageDirectory -DestinationPath $packageArchive -Force
$packageHash = Get-FileHash -LiteralPath $packageArchive -Algorithm SHA256
"$($packageHash.Hash)  $PackageName.zip" | Set-Content -LiteralPath (Join-Path $packageProject 'dist/SHA256SUMS.txt') -Encoding ascii
Get-Item -LiteralPath $packageArchive | Select-Object FullName,Length
