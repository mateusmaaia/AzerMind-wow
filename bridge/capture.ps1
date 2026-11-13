# Screen-captures the top-left corner of the WoW client window and decodes the
# AzerMind pixel strip (see Codec.lua in the addon). Prints one JSON line per
# new message to stdout. Started by bridge.js; can also be run by hand.
#
#   capture.ps1 -TestImage strip.png    decode a PNG once and exit (used by tests)

param(
  [int]$Cell = 4,
  [int]$Cells = 200,
  [int]$MaxRows = 96,
  [int]$IntervalMs = 250,
  [string]$ProcessName = "Wow",
  [string]$ClientFolder = "",
  [string]$TestImage = ""
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
$drawingAssemblies = @([System.Drawing.Bitmap].Assembly.Location, [System.Drawing.Color].Assembly.Location) | Select-Object -Unique
Add-Type -ReferencedAssemblies $drawingAssemblies -TypeDefinition @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;

public class CapWin {
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }

  public sealed class Strip {
    public int Id;
    public string Text;
    public string Error;
  }

  // The first five 3-bit cells come entirely from the 0xC7 0x1A magic.
  private static readonly int[] MagicCells = { 6, 1, 6, 1, 5 };
  private const int MinimumChannelContrast = 16;

  public static Strip Decode(Bitmap bitmap, int cellSize, int columns, int rows) {
    Strip strip = DecodeWithThresholds(bitmap, cellSize, columns, rows, 128, 128, 128);
    if (strip != null) return strip;

    // Screen capture can compress the RGB range. Use the known on/off cells
    // only after the default threshold misses the magic.
    int center = (int)Math.Round(cellSize / 2.0);
    var samples = new Color[MagicCells.Length];
    for (int i = 0; i < samples.Length; i++) {
      samples[i] = bitmap.GetPixel((i % columns) * cellSize + center, (i / columns) * cellSize + center);
    }
    int red = FindThreshold(samples, 2);
    int green = FindThreshold(samples, 1);
    int blue = FindThreshold(samples, 0);
    if (red < 0 || green < 0 || blue < 0) return null;
    return DecodeWithThresholds(bitmap, cellSize, columns, rows, red, green, blue);
  }

  private static int FindThreshold(Color[] samples, int channel) {
    int brightestOff = 0;
    int darkestOn = 255;
    for (int i = 0; i < samples.Length; i++) {
      int value = (samples[i].ToArgb() >> (channel * 8)) & 255;
      if ((MagicCells[i] & (1 << channel)) == 0) {
        brightestOff = Math.Max(brightestOff, value);
      } else {
        darkestOn = Math.Min(darkestOn, value);
      }
    }
    if (darkestOn - brightestOff < MinimumChannelContrast) return -1;
    return (brightestOff + darkestOn) / 2;
  }

  private static Strip DecodeWithThresholds(Bitmap bitmap, int cellSize, int columns, int rows,
      int red, int green, int blue) {
    var bytes = new byte[6];
    int count = 0;
    int acc = 0;
    int bits = 0;
    int totalCells = columns * rows;
    int center = (int)Math.Round(cellSize / 2.0);
    int width = bitmap.Width;
    int height = bitmap.Height;

    for (int i = 0; i < totalCells && count < bytes.Length; i++) {
      int x = (i % columns) * cellSize + center;
      int y = (i / columns) * cellSize + center;
      if (x >= width || y >= height) break;

      Color pixel = bitmap.GetPixel(x, y);
      int value = 0;
      if (pixel.R >= red) value |= 4;
      if (pixel.G >= green) value |= 2;
      if (pixel.B >= blue) value |= 1;
      acc = (acc << 3) | value;
      bits += 3;
      if (bits < 8) continue;

      bits -= 8;
      bytes[count++] = (byte)(acc >> bits);
      acc &= (1 << bits) - 1;
      if (count == 2 && (bytes[0] != 0xC7 || bytes[1] != 0x1A)) return null;
      if (count == 6) {
        int needed = 8 + bytes[4] * 256 + bytes[5];
        if (needed > Math.Round(totalCells * 3 / 8.0)) return new Strip { Error = "length" };
        Array.Resize(ref bytes, needed);
      }
    }

    if (count < bytes.Length) return new Strip { Error = "truncated" };
    int checksumIndex = count - 2;
    int s1 = 0;
    int s2 = 0;
    for (int i = 2; i < checksumIndex; i++) {
      s1 = (s1 + bytes[i]) % 255;
      s2 = (s2 + s1) % 255;
    }
    if (bytes[checksumIndex] != s1 || bytes[checksumIndex + 1] != s2) {
      return new Strip { Error = "checksum" };
    }
    return new Strip {
      Id = bytes[2] * 256 + bytes[3],
      Text = Encoding.UTF8.GetString(bytes, 6, checksumIndex - 6)
    };
  }
}
"@
[void][CapWin]::SetProcessDPIAware()

function Emit($obj) {
  [Console]::Out.WriteLine((ConvertTo-Json -Compress -InputObject $obj))
  [Console]::Out.Flush()
}

function Decode($bmp) {
  $strip = [CapWin]::Decode($bmp, $Cell, $Cells, $MaxRows)
  if ($null -eq $strip) { return $null }
  if ($strip.Error) { return @{ error = $strip.Error } }
  return @{ id = $strip.Id; text = $strip.Text }
}

if ($TestImage -ne "") {
  $bmp = [System.Drawing.Bitmap]::FromFile($TestImage)
  $msg = Decode $bmp
  $bmp.Dispose()
  if ($msg) { Emit $msg } else { Emit @{ error = "no valid strip in image" } }
  exit 0
}

$lastId = -1
$lastWarn = [DateTime]::MinValue
$proc = $null
$w = $Cells * $Cell
$h = $MaxRows * $Cell
while ($true) {
  if (-not $proc -or $proc.HasExited) {
    # Retail's exe is also Wow.exe: skip a game running from another client folder.
    $proc = Get-Process $ProcessName -ErrorAction SilentlyContinue | Where-Object {
      $_.MainWindowHandle -ne 0 -and (-not $ClientFolder -or -not $_.Path -or (Split-Path -Leaf (Split-Path -Parent $_.Path)) -eq $ClientFolder)
    } | Select-Object -First 1
    if (-not $proc) {
      Emit @{ info = "waiting for $ProcessName window$(if ($ClientFolder) { " in $ClientFolder" })" }
      Start-Sleep -Seconds 3
      continue
    }
    Emit @{ info = "attached to '$($proc.MainWindowTitle)' (pid $($proc.Id))" }
  }
  $hwnd = $proc.MainWindowHandle
  if ([CapWin]::IsIconic($hwnd)) { Start-Sleep -Milliseconds 1000; continue }
  $pt = New-Object CapWin+POINT
  [void][CapWin]::ClientToScreen($hwnd, [ref]$pt)
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $ok = $true
  try { $g.CopyFromScreen($pt.X, $pt.Y, 0, 0, $bmp.Size) } catch { $ok = $false }
  $g.Dispose()
  if ($ok) {
    $msg = Decode $bmp
    if ($msg -and $msg.error) {
      # Magic matched but the frame didn't validate: say so, at most every 5 s.
      if (([DateTime]::Now - $lastWarn).TotalSeconds -ge 5) {
        $lastWarn = [DateTime]::Now
        Emit @{ warn = "strip seen but rejected: $($msg.error)" }
      }
    } elseif ($msg) {
      $key = "$($msg.id):$($msg.text)"
      if ($key -ne $lastId) {
        $lastId = $key
        Emit $msg
      }
    }
  }
  $bmp.Dispose()
  Start-Sleep -Milliseconds $IntervalMs
}
