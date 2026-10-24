param([switch]$Pattern, [string]$Output = 'docs/screenshots/transfer-shadow.png')
. (Join-Path $PSScriptRoot 'window_target.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class GlassCapture {
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c,string t);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr w,out RECT r);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr w,int cmd);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr w);
 [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
 public struct RECT {public int left,top,right,bottom;}
}
"@
[GlassCapture]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
$glassHandle=(Get-ClipboardTestWindow '悬浮中转')
$glassRect=New-Object GlassCapture+RECT
[GlassCapture]::GetWindowRect($glassHandle,[ref]$glassRect) | Out-Null
$glassBackground=[Windows.Forms.Form]::new()
$glassBackground.FormBorderStyle='None'; $glassBackground.StartPosition='Manual'
$glassBackground.Location=[Drawing.Point]::new(($glassRect.left-48),($glassRect.top-48))
$glassBackground.Size=[Drawing.Size]::new(($glassRect.right-$glassRect.left+96),($glassRect.bottom-$glassRect.top+96))
$glassBackground.BackColor=[Drawing.Color]::FromArgb(218,228,244)
if ($Pattern) {
 $glassBackground.Add_Paint({ param($sender,$event)
  $brushA=[Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(85,145,225))
  $brushB=[Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(233,171,192))
  for($stripe=0;$stripe -lt $sender.Width;$stripe+=80){
   $brush=if(($stripe/80)%2 -eq 0){$brushA}else{$brushB}
   $event.Graphics.FillRectangle($brush,$stripe,0,40,$sender.Height)
  }
  $brushA.Dispose();$brushB.Dispose()
 })
}
[GlassCapture]::ShowWindow((Get-ClipboardTestWindow '口袋Cube'),0) | Out-Null
$glassBackground.Show()
[GlassCapture]::ShowWindow($glassHandle,9) | Out-Null
[GlassCapture]::SetForegroundWindow($glassHandle) | Out-Null
[Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 500
$glassBitmap=[Drawing.Bitmap]::new($glassBackground.Width,$glassBackground.Height)
$glassGraphics=[Drawing.Graphics]::FromImage($glassBitmap)
$glassGraphics.CopyFromScreen($glassBackground.Left,$glassBackground.Top,0,0,$glassBitmap.Size)
$glassBitmap.Save((Join-Path (Get-Location) $Output),[Drawing.Imaging.ImageFormat]::Png)
$glassGraphics.Dispose(); $glassBitmap.Dispose(); $glassBackground.Close(); $glassBackground.Dispose()
Write-Output $Output
