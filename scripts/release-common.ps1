function Invoke-ReleaseCommand([string]$Command, [string[]]$CommandArguments) {
  & $Command @CommandArguments
  if ($LASTEXITCODE -ne 0) { throw "执行失败：$Command（退出码 $LASTEXITCODE）" }
}
function Get-ReleaseVersion([string]$Project) {
  $match = [regex]::Match([IO.File]::ReadAllText((Join-Path $Project 'pubspec.yaml')), '(?m)^version:\s*(\d+\.\d+\.\d+)')
  if (-not $match.Success) { throw '无法从 pubspec.yaml 读取版本。' }
  return $match.Groups[1].Value
}
function Get-FlutterRunner {
  $command = Get-Command flutter -ErrorAction Stop
  $bin = Split-Path $command.Source -Parent
  $dart = Join-Path $bin 'cache/dart-sdk/bin/dart.exe'
  $snapshot = Join-Path $bin 'cache/flutter_tools.snapshot'
  if ((Test-Path -LiteralPath $dart) -and (Test-Path -LiteralPath $snapshot)) {
    return @{Command=$dart; Prefix=@($snapshot)}
  }
  return @{Command=$command.Source; Prefix=@()}
}
function Invoke-FlutterRelease([hashtable]$Runner, [string[]]$FlutterArguments) {
  Invoke-ReleaseCommand $Runner.Command ($Runner.Prefix + $FlutterArguments)
}
