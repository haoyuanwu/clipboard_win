param([string]$Output = 'docs/screenshots/windows-main.png', [string]$Title = 'SuperClipboard')
. (Join-Path $PSScriptRoot 'window_target.ps1')
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class WindowCapture {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string className, string title);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out RECT rect);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr window, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr wp, IntPtr lp);
  public struct RECT { public int left, top, right, bottom; }
}
"@
[WindowCapture]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
$clipboardWindow = (Get-ClipboardTestWindow $Title)
if ($clipboardWindow -eq [IntPtr]::Zero) { throw 'SuperClipboard window not found' }
$clipboardRect = New-Object WindowCapture+RECT
[WindowCapture]::GetWindowRect($clipboardWindow, [ref]$clipboardRect) | Out-Null
$clipboardBitmap = [Drawing.Bitmap]::new($clipboardRect.right - $clipboardRect.left, $clipboardRect.bottom - $clipboardRect.top)
$clipboardGraphics = [Drawing.Graphics]::FromImage($clipboardBitmap)
$clipboardDC = $clipboardGraphics.GetHdc()
[WindowCapture]::PrintWindow($clipboardWindow, $clipboardDC, 2) | Out-Null
$clipboardGraphics.ReleaseHdc($clipboardDC)
$clipboardBitmap.Save((Join-Path (Get-Location) $Output), [Drawing.Imaging.ImageFormat]::Png)
$clipboardGraphics.Dispose(); $clipboardBitmap.Dispose()
Write-Output $Output
