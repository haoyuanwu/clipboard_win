# Resolve only the explicitly recorded verification process, never a user's app.
if (-not ('ClipboardWindowTarget' -as [type])) {
 Add-Type @"
using System; using System.Runtime.InteropServices;
public static class ClipboardWindowTarget {
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr FindWindowEx(IntPtr parent,IntPtr after,string cls,string title);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr w,out uint pid);
 public static IntPtr Find(int pid,string title) {
  IntPtr current=IntPtr.Zero;
  while((current=FindWindowEx(IntPtr.Zero,current,"FLUTTER_RUNNER_WIN32_WINDOW",title))!=IntPtr.Zero) {
   uint owner;GetWindowThreadProcessId(current,out owner);
   if(owner==(uint)pid)return current;
  }
  return IntPtr.Zero;
 }
}
"@
}
function Get-ClipboardTestWindow([string]$Title) {
 $targetFile=Join-Path $PSScriptRoot '../build/preview-pid.txt'
 if(-not (Test-Path -LiteralPath $targetFile)){throw 'Verification process id is required'}
 $targetProcessId=[int](Get-Content -LiteralPath $targetFile)
 return [ClipboardWindowTarget]::Find($targetProcessId,$Title)
}
