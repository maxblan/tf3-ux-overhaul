# Moves the mouse to a screen pixel of the game and clicks there (spec/ingame/run.sh, "[testbench]
# MOUSE x y" / "CLICK x y"). The cursor goes a few pixels off and back, so the game sees it move, and
# stays there for the next shot. A click only goes out when the game's window is the one at that
# pixel: the game is brought to the front first, and where another window still lies over it the
# click is skipped (logged), so it never lands in another program.
# The helper is compiled once before the game starts (-build): compiling it while the game ran hung
# (observed).
# Usage: powershell -File mouse.ps1 -dll C:\path\uio_mouse.dll -build
#        powershell -File mouse.ps1 -dll C:\path\uio_mouse.dll -x 100 -y 200 [-click]
param([string]$dll, [switch]$build, [int]$x, [int]$y, [switch]$click)
if ($build) {
	Add-Type -OutputAssembly $dll -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class UioMouse {
  [DllImport("user32.dll")] public static extern void mouse_event(int flags, int dx, int dy, int data, int extra);
  [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
  [DllImport("user32.dll")] static extern int GetWindowThreadProcessId(IntPtr window, out int process);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
  public struct Point { public int X, Y; }
  // the process whose window lies at screen pixel x, y
  public static int ProcessAt(int x, int y) {
    Point point; point.X = x; point.Y = y;
    int process; GetWindowThreadProcessId(WindowFromPoint(point), out process);
    return process;
  }
}
"@
	exit 0
}
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Reflection.Assembly]::LoadFile($dll) | Out-Null
$game = Get-Process TransportFever3 -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $game) { "skipped $x,$y`: the game is not running"; exit 0 }
if ([UioMouse]::ProcessAt($x, $y) -ne $game.Id) {
	[UioMouse]::SetForegroundWindow($game.MainWindowHandle) | Out-Null
	Start-Sleep -Milliseconds 400
}
$on_game = [UioMouse]::ProcessAt($x, $y) -eq $game.Id
if ($click -and -not $on_game) { "skipped the click at $x,$y`: another window lies over the game there"; exit 0 }
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point ($x - 6), ($y - 6)
Start-Sleep -Milliseconds 120
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point $x, $y
if ($click) {
	Start-Sleep -Milliseconds 150
	[UioMouse]::mouse_event(2, 0, 0, 0, 0) # left button down
	Start-Sleep -Milliseconds 80
	[UioMouse]::mouse_event(4, 0, 0, 0, 0) # left button up
	"clicked $x,$y"
}
