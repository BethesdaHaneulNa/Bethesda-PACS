# Bethesda CD - its icon, drawn here (no picture file is fetched from anywhere).
#
#   .\make-icon.ps1 -Out ..\build\Bethesda-CD.ico              the icon (16, 32, 48, 256)
#   .\make-icon.ps1 -Variant B -Out x.ico                      another of the candidates
#   .\make-icon.ps1 -Sheet candidates.png                      all candidates side by side, to choose from
#
# A: a white disc on the EMR's blue          B: the disc alone, silver, blue label
# C: a blue disc with the white cross of a clinic
param([ValidateSet('A', 'B', 'C')][string]$Variant = 'A', [string]$Out = '', [string]$Sheet = '')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$BLUE = [Drawing.Color]::FromArgb(0x3B, 0x82, 0xF6)        # the EMR's accent
$DEEP = [Drawing.Color]::FromArgb(0x1D, 0x4E, 0xD8)

function New-Icon([string]$Kind, [int]$S) {
  $bmp = New-Object Drawing.Bitmap($S, $S, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'; $g.Clear([Drawing.Color]::Transparent)
  $u = $S / 64.0                                           # everything is laid out on a 64-unit square
  function Ring($brush, [double]$cx, [double]$cy, [double]$r) { $g.FillEllipse($brush, [single](($cx - $r) * $u), [single](($cy - $r) * $u), [single](2 * $r * $u), [single](2 * $r * $u)) }
  function Solid($c) { New-Object Drawing.SolidBrush($c) }
  switch ($Kind) {
    'A' {
      # a rounded square of the EMR's blue, a white disc on it
      $r = 13 * $u; $d = 2 * $r; $w = $S - 1
      $p = New-Object Drawing.Drawing2D.GraphicsPath
      $p.AddArc(0, 0, $d, $d, 180, 90); $p.AddArc($w - $d, 0, $d, $d, 270, 90); $p.AddArc($w - $d, $w - $d, $d, $d, 0, 90); $p.AddArc(0, $w - $d, $d, $d, 90, 90); $p.CloseFigure()
      $grad = New-Object Drawing.Drawing2D.LinearGradientBrush((New-Object Drawing.PointF(0, 0)), (New-Object Drawing.PointF(0, $S)), $BLUE, $DEEP)
      $g.FillPath($grad, $p)
      Ring (Solid ([Drawing.Color]::White)) 32 32 22
      Ring (Solid ([Drawing.Color]::FromArgb(0xDB, 0xE8, 0xFE))) 32 32 10
      Ring (Solid $DEEP) 32 32 4.5
    }
    'B' {
      # the disc alone: a silver body, a blue label ring, the hole
      Ring (Solid ([Drawing.Color]::FromArgb(0x64, 0x74, 0x8B))) 32 32 31
      $silver = New-Object Drawing.Drawing2D.LinearGradientBrush((New-Object Drawing.PointF(0, 0)), (New-Object Drawing.PointF($S, $S)), [Drawing.Color]::FromArgb(0xF8, 0xFA, 0xFC), [Drawing.Color]::FromArgb(0xB6, 0xC2, 0xD2))
      Ring $silver 32 32 29
      Ring (Solid $BLUE) 32 32 14
      Ring (Solid ([Drawing.Color]::White)) 32 32 7
      Ring (Solid ([Drawing.Color]::FromArgb(0x64, 0x74, 0x8B))) 32 32 4
      Ring (Solid ([Drawing.Color]::Transparent)) 32 32 0
    }
    'C' {
      # a blue disc, the white cross of a clinic across it
      Ring (Solid $DEEP) 32 32 31
      Ring (Solid $BLUE) 32 32 29
      $white = Solid ([Drawing.Color]::White)
      $g.FillRectangle($white, [single](26 * $u), [single](12 * $u), [single](12 * $u), [single](40 * $u))
      $g.FillRectangle($white, [single](12 * $u), [single](26 * $u), [single](40 * $u), [single](12 * $u))
      Ring (Solid $DEEP) 32 32 4.5
    }
  }
  $g.Dispose()
  return $bmp
}

# An .ico file: 16, 32 and 48 as plain bitmaps (read everywhere), 256 as PNG.
function Save-Ico([string]$Kind, [string]$Path) {
  $sizes = 16, 32, 48, 256
  $blobs = foreach ($s in $sizes) {
    $bmp = New-Icon $Kind $s
    $ms = New-Object IO.MemoryStream
    if ($s -ge 256) { $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png) }
    else {
      $w = New-Object IO.BinaryWriter($ms)
      $w.Write([int]40); $w.Write([int]$s); $w.Write([int]($s * 2)); $w.Write([int16]1); $w.Write([int16]32); $w.Write([int]0); $w.Write([int]($s * $s * 4)); $w.Write([int]0); $w.Write([int]0); $w.Write([int]0); $w.Write([int]0)
      for ($y = $s - 1; $y -ge 0; $y--) { for ($x = 0; $x -lt $s; $x++) { $c = $bmp.GetPixel($x, $y); $w.Write([byte]$c.B); $w.Write([byte]$c.G); $w.Write([byte]$c.R); $w.Write([byte]$c.A) } }
      $mask = New-Object byte[] ([int]([Math]::Ceiling($s / 32.0)) * 4 * $s); $w.Write($mask); $w.Flush()
    }
    $bmp.Dispose(); , $ms.ToArray()
  }
  $out = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter($out)
  $w.Write([int16]0); $w.Write([int16]1); $w.Write([int16]$sizes.Count)
  $at = 6 + 16 * $sizes.Count
  for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]; $b = [byte]$(if ($s -ge 256) { 0 } else { $s })
    $w.Write($b); $w.Write($b); $w.Write([byte]0); $w.Write([byte]0); $w.Write([int16]1); $w.Write([int16]32); $w.Write([int]$blobs[$i].Length); $w.Write([int]$at)
    $at += $blobs[$i].Length
  }
  foreach ($b in $blobs) { $w.Write($b) }
  $w.Flush(); [IO.File]::WriteAllBytes($Path, $out.ToArray())
}

if ($Sheet) {
  # the candidates side by side, each at 256, 48, 32 and 16, on a light and on a dark ground
  $kinds = 'A', 'B', 'C'; $cell = 300; $W = $cell * $kinds.Count; $H = 470
  $page = New-Object Drawing.Bitmap($W, $H); $g = [Drawing.Graphics]::FromImage($page); $g.Clear([Drawing.Color]::White)
  $font = New-Object Drawing.Font('Segoe UI', 14, [Drawing.FontStyle]::Bold); $small = New-Object Drawing.Font('Segoe UI', 9)
  for ($k = 0; $k -lt $kinds.Count; $k++) {
    $x0 = $k * $cell
    $g.DrawString($kinds[$k], $font, [Drawing.Brushes]::Black, ($x0 + 14), 8)
    $b = New-Icon $kinds[$k] 256; $g.DrawImageUnscaled($b, ($x0 + 22), 44); $b.Dispose()
    $g.FillRectangle([Drawing.Brushes]::WhiteSmoke, ($x0 + 14), 316, 272, 64); $g.FillRectangle((New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(0x1F, 0x29, 0x37))), ($x0 + 14), 388, 272, 64)
    $x = $x0 + 30
    foreach ($s in 48, 32, 16) { $b = New-Icon $kinds[$k] $s; $g.DrawImageUnscaled($b, $x, (348 - [int]($s / 2))); $g.DrawImageUnscaled($b, $x, (420 - [int]($s / 2))); $b.Dispose(); $x += $s + 30 }
    $g.DrawString('48 / 32 / 16', $small, [Drawing.Brushes]::Gray, ($x0 + 200), 340)
  }
  $g.Dispose(); $page.Save($Sheet, [Drawing.Imaging.ImageFormat]::Png); $page.Dispose()
  "candidates: $Sheet"
}
if ($Out) { Save-Ico $Variant $Out; "icon ($Variant): $Out, $((Get-Item $Out).Length) bytes" }
