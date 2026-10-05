# Saves the game window's content to a PNG (spec/ingame/run.sh, "[testbench] SHOT <name>").
# PrintWindow renders the window itself, so the shot shows the game even when other windows lie in
# front of it, and never anything else on the screen (observed with the Vulkan renderer, 2026-10-05).
# Usage: powershell -File window_shot.ps1 -out C:\path\shot.png
param([string]$out)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class UioWindowShot {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr window, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr window, out Rect rect);
  public struct Rect { public int Left, Top, Right, Bottom; }
}
"@
$game = Get-Process TransportFever3 -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $game -or $game.MainWindowHandle -eq [IntPtr]::Zero) { exit 1 }
$rect = New-Object UioWindowShot+Rect
[UioWindowShot]::GetClientRect($game.MainWindowHandle, [ref]$rect) | Out-Null
$bitmap = New-Object System.Drawing.Bitmap ($rect.Right - $rect.Left), ($rect.Bottom - $rect.Top)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$dc = $graphics.GetHdc()
# 3 = PW_CLIENTONLY | PW_RENDERFULLCONTENT (needed for windows the GPU draws)
[UioWindowShot]::PrintWindow($game.MainWindowHandle, $dc, 3) | Out-Null
$graphics.ReleaseHdc($dc)
$bitmap.Save($out)
