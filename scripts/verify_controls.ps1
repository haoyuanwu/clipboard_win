param([switch]$MacStyle)
. ./scripts/verify_windows.ps1 -MacStyle:$MacStyle
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class WindowStateProbe {
 [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr w);
 [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr w);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr w);
}
"@
if($MacStyle){[ClipboardUi]::Click($uiMain,40,23)}else{[ClipboardUi]::Click($uiMain,($uiWidth-115),16)}
Start-Sleep -Milliseconds 300
if(-not [WindowStateProbe]::IsIconic($uiMain)){throw 'Minimize control failed'}
[ClipboardUi]::ShowWindow($uiMain,9) | Out-Null
Start-Sleep -Milliseconds 200
if($MacStyle){[ClipboardUi]::Click($uiMain,60,23)}else{[ClipboardUi]::Click($uiMain,($uiWidth-69),16)}
Start-Sleep -Milliseconds 300
$zoomRect=New-Object ClipboardUi+RECT
[ClipboardUi]::GetClientRect($uiMain,[ref]$zoomRect) | Out-Null
$zoomWidth=$zoomRect.right/([ClipboardUi]::GetDpiForWindow($uiMain)/96.0)
if($MacStyle){if($zoomWidth -gt 461){throw "Mac zoom exceeded source maximum width: $zoomWidth"}}
else{
 if(-not [WindowStateProbe]::IsZoomed($uiMain) -or $zoomWidth -le 460){throw "Windows maximize failed: $zoomWidth"}
 [ClipboardUi]::Click($uiMain,($zoomWidth-69),16)
 Start-Sleep -Milliseconds 300
 if([WindowStateProbe]::IsZoomed($uiMain)){throw 'Restore caption button failed'}
}
[ClipboardUi]::ShowWindow($uiMain,9) | Out-Null
Start-Sleep -Milliseconds 200
if($MacStyle){[ClipboardUi]::Click($uiMain,20,23)}else{[ClipboardUi]::Click($uiMain,($uiWidth-23),16)}
Start-Sleep -Milliseconds 200
if([WindowStateProbe]::IsWindowVisible($uiMain)){throw 'Close control did not hide main window'}
Write-Output "Window controls passed; zoom width $zoomWidth"
