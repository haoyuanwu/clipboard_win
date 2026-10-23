param([switch]$MacStyle)
. (Join-Path $PSScriptRoot 'window_target.ps1')
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class ClipboardUi {
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls,string title);
 [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr window,uint cmd);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr window,out RECT rect);
 [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr window);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window,int cmd);
 [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr window,uint msg,IntPtr wp,IntPtr lp);
 [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
 public struct RECT {public int left,top,right,bottom;}
 public static void Click(IntPtr parent,double x,double y) {
   IntPtr view=GetWindow(parent,5); double scale=GetDpiForWindow(parent)/96.0;
   int px=(int)(x*scale), py=(int)(y*scale); IntPtr point=(IntPtr)((py<<16)|(px&65535));
   SendMessage(view,0x200,IntPtr.Zero,point); SendMessage(view,0x201,(IntPtr)1,point); SendMessage(view,0x202,IntPtr.Zero,point);
 }
}
"@
[ClipboardUi]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
$uiMain=(Get-ClipboardTestWindow 'SuperClipboard')
if ($uiMain -eq [IntPtr]::Zero) {throw 'Main window missing'}
[ClipboardUi]::ShowWindow($uiMain,9) | Out-Null
$uiRect = New-Object ClipboardUi+RECT
[ClipboardUi]::GetClientRect($uiMain,[ref]$uiRect) | Out-Null
$uiWidth=$uiRect.right/([ClipboardUi]::GetDpiForWindow($uiMain)/96.0)
if($MacStyle){[ClipboardUi]::Click($uiMain,($uiWidth-65),26)}else{[ClipboardUi]::Click($uiMain,($uiWidth-61),54)}
Start-Sleep -Milliseconds 1400
$uiTransfer=(Get-ClipboardTestWindow '悬浮中转')
if ($uiTransfer -eq [IntPtr]::Zero) {throw 'Transfer window missing'}
[ClipboardUi]::SendMessage($uiMain,0x801f,[IntPtr]::Zero,[IntPtr]0x202) | Out-Null
Start-Sleep -Milliseconds 1400
$uiPopover=(Get-ClipboardTestWindow 'SuperClipboard 快捷历史')
if ($uiPopover -eq [IntPtr]::Zero) {throw 'Popover missing'}
Write-Output 'Main, transfer and tray popover windows created successfully'
& ./scripts/capture_window.ps1 -Output docs/screenshots/windows-popover.png -Title 'SuperClipboard 快捷历史'
[ClipboardUi]::ShowWindow($uiMain,9) | Out-Null
& ./scripts/capture_window.ps1 -Output docs/screenshots/windows-main.png
& ./scripts/capture_window.ps1 -Output docs/screenshots/windows-transfer.png -Title '悬浮中转'
