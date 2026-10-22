. ./scripts/verify_windows.ps1
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class WindowStateProbe {
 [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr w);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr w);
}
"@
[ClipboardUi]::Click($uiMain,40,23)
Start-Sleep -Milliseconds 300
if(-not [WindowStateProbe]::IsIconic($uiMain)){throw 'Minimize control failed'}
[ClipboardUi]::ShowWindow($uiMain,9) | Out-Null
Start-Sleep -Milliseconds 200
[ClipboardUi]::Click($uiMain,60,23)
Start-Sleep -Milliseconds 300
$zoomRect=New-Object ClipboardUi+RECT
[ClipboardUi]::GetClientRect($uiMain,[ref]$zoomRect) | Out-Null
$zoomWidth=$zoomRect.right/([ClipboardUi]::GetDpiForWindow($uiMain)/96.0)
if($zoomWidth -gt 461){throw "Zoom exceeded source maximum width: $zoomWidth"}
[ClipboardUi]::ShowWindow($uiMain,9) | Out-Null
Start-Sleep -Milliseconds 200
[ClipboardUi]::Click($uiMain,20,23)
Start-Sleep -Milliseconds 200
if([WindowStateProbe]::IsWindowVisible($uiMain)){throw 'Close control did not hide main window'}
Write-Output "Window controls passed; zoom width $zoomWidth"
