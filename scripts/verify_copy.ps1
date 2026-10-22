Add-Type -AssemblyName System.Windows.Forms
. ./scripts/verify_windows.ps1
$writeBackup = [Windows.Forms.DataObject]::new()
$writeCurrent = [Windows.Forms.Clipboard]::GetDataObject()
if ($null -ne $writeCurrent) {
 foreach ($writeFormat in $writeCurrent.GetFormats($false)) {
  try {
   $writeValue = $writeCurrent.GetData($writeFormat,$false)
   if ($writeValue -is [Drawing.Bitmap]) {$writeValue = $writeValue.Clone()}
   elseif ($writeValue -is [IO.MemoryStream]) {$writeValue = [IO.MemoryStream]::new($writeValue.ToArray())}
   if ($null -ne $writeValue) {$writeBackup.SetData($writeFormat,$false,$writeValue)}
  } catch {}
 }
}
try {
 $writeStateBefore=Get-Content build/preview-data/state.json -Raw | ConvertFrom-Json
 $writeEntryBefore=@($writeStateBefore.history | Where-Object text -eq '让每一次复制，都有迹可循。')[0]
 [ClipboardUi]::ShowWindow($uiPopover,9) | Out-Null
 [ClipboardUi]::Click($uiPopover,100,140)
 Start-Sleep -Milliseconds 500
 $writeText=[Windows.Forms.Clipboard]::GetText([Windows.Forms.TextDataFormat]::UnicodeText)
 $writeStateAfter=Get-Content build/preview-data/state.json -Raw | ConvertFrom-Json
 $writeEntryAfter=@($writeStateAfter.history | Where-Object text -eq '让每一次复制，都有迹可循。')[0]
 if ($writeText -ne '让每一次复制，都有迹可循。') {throw 'Popover copy did not write expected text'}
 if ($writeEntryAfter.count -ne ($writeEntryBefore.count+1)) {throw 'Self-copy notification inflated copy count'}
 Write-Output 'Native clipboard write and self-copy suppression passed'
} finally {
 try {
  if ($writeBackup.GetFormats($false).Count -gt 0) {[Windows.Forms.Clipboard]::SetDataObject($writeBackup,$true,20,100)}
  Write-Output 'Previous clipboard restored from materialized snapshot'
 } catch {Write-Warning 'Clipboard restore failed; test clipboard remains active'}
}
