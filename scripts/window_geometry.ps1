. (Join-Path $PSScriptRoot 'window_target.ps1')
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class ClipboardGeometry {
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c,string t);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr w,out RECT r);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr w,out RECT r);
 [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr w,uint c);
 [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr w);
 [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
 public struct RECT {public int left,top,right,bottom;}
}
"@
[ClipboardGeometry]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
foreach($geometryTitle in @('SuperClipboard','SuperClipboard 快捷历史','悬浮中转')) {
 $geometryHandle=(Get-ClipboardTestWindow $geometryTitle)
 $geometryWindow=New-Object ClipboardGeometry+RECT; $geometryClient=New-Object ClipboardGeometry+RECT; $geometryChild=New-Object ClipboardGeometry+RECT
 [ClipboardGeometry]::GetWindowRect($geometryHandle,[ref]$geometryWindow) | Out-Null
 [ClipboardGeometry]::GetClientRect($geometryHandle,[ref]$geometryClient) | Out-Null
 [ClipboardGeometry]::GetWindowRect([ClipboardGeometry]::GetWindow($geometryHandle,5),[ref]$geometryChild) | Out-Null
 [pscustomobject]@{title=$geometryTitle;dpi=[ClipboardGeometry]::GetDpiForWindow($geometryHandle);window=$geometryWindow;client=$geometryClient;child=$geometryChild} | ConvertTo-Json -Compress
}
