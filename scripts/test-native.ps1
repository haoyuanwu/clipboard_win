#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$cache = Join-Path $project 'build/windows/x64/CMakeCache.txt'
if (-not (Test-Path -LiteralPath $cache)) { throw '请先完成 Flutter Windows 构建。' }
function Read-CMakeValue([string]$key) {
  $match = Select-String -LiteralPath $cache -Pattern "^${key}:INTERNAL=(.+)$" | Select-Object -First 1
  if ($match) { return $match.Matches[0].Groups[1].Value }
  return ''
}
$generator = Read-CMakeValue 'CMAKE_GENERATOR'
$instance = Read-CMakeValue 'CMAKE_GENERATOR_INSTANCE'
$cmake = Get-Command cmake -ErrorAction SilentlyContinue
if ($cmake) { $cmakePath = $cmake.Source }
else { $cmakePath = Join-Path $instance 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe' }
if (-not (Test-Path -LiteralPath $cmakePath)) { throw '未找到 CMake，请安装 Visual Studio C++ CMake 工具。' }
$build = Join-Path $project 'build/native-tests'
& $cmakePath -S (Join-Path $PSScriptRoot 'native_tests') -B $build -G $generator -A x64 "-DCMAKE_GENERATOR_INSTANCE=$instance"
if ($LASTEXITCODE -ne 0) { throw '原生测试配置失败。' }
& $cmakePath --build $build --config Release
if ($LASTEXITCODE -ne 0) { throw '原生测试编译失败。' }
$work = Join-Path $build "work-$([Guid]::NewGuid().ToString('N'))"
& (Join-Path $build 'Release/native_transfer_test.exe') $work
if ($LASTEXITCODE -ne 0) { throw "原生文件拖放测试失败：$LASTEXITCODE" }
Remove-Item -LiteralPath $work
