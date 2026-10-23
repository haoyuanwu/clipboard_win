# Test only the isolated process recorded by window_target.ps1.
. (Join-Path $PSScriptRoot 'window_target.ps1')
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class ClipboardHotkeyProbe {
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr w);
 [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr w,uint msg,IntPtr wp,IntPtr lp);
 [DllImport("user32.dll")] public static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
 public static void Chord(byte key) {
  keybd_event(0x11,0,0,UIntPtr.Zero);keybd_event(0x12,0,0,UIntPtr.Zero);
  keybd_event(key,0,0,UIntPtr.Zero);keybd_event(key,0,2,UIntPtr.Zero);
  keybd_event(0x12,0,2,UIntPtr.Zero);keybd_event(0x11,0,2,UIntPtr.Zero);
 }
}
"@
$tests = @(@{key=67;title='SuperClipboard 快捷历史'},@{key=86;title='悬浮中转'})
foreach ($test in $tests) {
 $window = Get-ClipboardTestWindow $test.title
 if ($window -ne [IntPtr]::Zero) { [ClipboardHotkeyProbe]::SendMessage($window,0x10,[IntPtr]::Zero,[IntPtr]::Zero) | Out-Null }
 [ClipboardHotkeyProbe]::Chord([byte]$test.key)
 Start-Sleep -Milliseconds 900
 $window = Get-ClipboardTestWindow $test.title
 if ($window -eq [IntPtr]::Zero -or -not [ClipboardHotkeyProbe]::IsWindowVisible($window)) { throw "Global hotkey did not open $($test.title)" }
 [ClipboardHotkeyProbe]::Chord([byte]$test.key)
 Start-Sleep -Milliseconds 350
 if ([ClipboardHotkeyProbe]::IsWindowVisible($window)) { throw "Global hotkey did not hide $($test.title)" }
}
Write-Output 'Both global shortcuts opened and hid their windows while the main window was hidden.'
