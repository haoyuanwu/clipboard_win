param([string]$DataDir = 'build/smoke-data')
Add-Type -AssemblyName System.Windows.Forms
$clipboardTestText = 'SuperClipboard Windows 原生文字验证 ' + [Guid]::NewGuid().ToString('N')
$clipboardPrevious = [Windows.Forms.DataObject]::new()
$clipboardExisting = [Windows.Forms.Clipboard]::GetDataObject()
if ($null -ne $clipboardExisting) {
 foreach ($clipboardFormat in $clipboardExisting.GetFormats($false)) {
  try {
   $clipboardValue = $clipboardExisting.GetData($clipboardFormat,$false)
   if ($clipboardValue -is [Drawing.Bitmap]) {$clipboardValue = $clipboardValue.Clone()}
   elseif ($clipboardValue -is [IO.MemoryStream]) {$clipboardValue = [IO.MemoryStream]::new($clipboardValue.ToArray())}
   if ($null -ne $clipboardValue) {$clipboardPrevious.SetData($clipboardFormat,$false,$clipboardValue)}
  } catch {}
 }
}
$clipboardResults = [Collections.Generic.List[object]]::new()
try {
  [Windows.Forms.Clipboard]::SetText($clipboardTestText)
  Start-Sleep -Milliseconds 600
  [Windows.Forms.Clipboard]::SetText($clipboardTestText)
  Start-Sleep -Milliseconds 600
  $clipboardData = [Windows.Forms.DataObject]::new()
  $clipboardData.SetText('富文本验证', [Windows.Forms.TextDataFormat]::UnicodeText)
  $clipboardData.SetText('{\rtf1\ansi\b Rich text\b0\par preserved}', [Windows.Forms.TextDataFormat]::Rtf)
  [Windows.Forms.Clipboard]::SetDataObject($clipboardData, $true)
  Start-Sleep -Milliseconds 600
  $clipboardPaths = [Collections.Specialized.StringCollection]::new()
  $clipboardFixture = Join-Path (Get-Location) 'build/smoke-file.txt'
  '独立副本测试文件' | Set-Content -LiteralPath $clipboardFixture -Encoding utf8
  [void]$clipboardPaths.Add($clipboardFixture)
  [Windows.Forms.Clipboard]::SetFileDropList($clipboardPaths)
  Start-Sleep -Milliseconds 600
  $clipboardImage = [Drawing.Bitmap]::FromFile((Join-Path (Get-Location) 'assets/app_logo.png'))
  [Windows.Forms.Clipboard]::SetImage($clipboardImage)
  Start-Sleep -Milliseconds 900
  $clipboardImage.Dispose()
  $clipboardState = Get-Content -LiteralPath (Join-Path $DataDir 'state.json') -Raw | ConvertFrom-Json
  $clipboardText = @($clipboardState.history | Where-Object text -eq $clipboardTestText)
  $clipboardResults.Add(@{name='Unicode text listener and duplicate merge'; passed=($clipboardText.Count -eq 1 -and $clipboardText[0].count -eq 2)})
  $clipboardResults.Add(@{name='RTF payload captured'; passed=(@($clipboardState.history | Where-Object {$_.rtf -like '*Rich text*'}).Count -eq 1)})
  $clipboardResults.Add(@{name='File path captured'; passed=(@($clipboardState.history | Where-Object kind -eq file).Count -ge 1)})
  $clipboardResults.Add(@{name='DIB image captured and saved'; passed=(@($clipboardState.history | Where-Object kind -eq image).Count -ge 1)})
  $clipboardResults | ConvertTo-Json | Set-Content -LiteralPath 'docs/native-verification.json' -Encoding utf8
  $clipboardResults | Format-Table
  if (@($clipboardResults | Where-Object {-not $_.passed}).Count -ne 0) { throw 'Native clipboard verification failed' }
} finally {
  if ($null -ne $clipboardPrevious) { [Windows.Forms.Clipboard]::SetDataObject($clipboardPrevious, $true, 20, 100) }
  else { [Windows.Forms.Clipboard]::Clear() }
}
