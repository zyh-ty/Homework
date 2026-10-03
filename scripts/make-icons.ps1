# Regenerates src-tauri/icons/icon.ico as a standard multi-size Windows icon.
#
# Why: the scaffolded icon.ico stored every frame (including 16/24/32/48/64) as a
# PNG-compressed entry, and omitted the sizes Windows commonly asks for (20/40/96/128).
# Windows therefore had to rescale, and the taskbar (window icon rasterised from the
# exe resource at the system icon metric) and Explorer (frames picked from the ICO)
# could disagree. This script writes the conventional layout instead:
#   - 16/20/24/32/40/48/64/96/128  -> 32bpp DIB (BITMAPINFOHEADER + BGRA, bottom-up,
#     all-zero AND mask; alpha carries transparency)
#   - 256                          -> PNG
#
# Uses only System.Drawing from the .NET Framework, so no extra dependencies.
# Run with Windows PowerShell 5.1:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\make-icons.ps1

param(
  [string]$Source = (Join-Path $PSScriptRoot "..\src-tauri\icons\icon.png"),
  [string]$OutDir = (Join-Path $PSScriptRoot "..\src-tauri\icons")
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

function U16([int]$v) {
  [byte]($v -band 0xFF), [byte](($v -shr 8) -band 0xFF)
}

function U32([long]$v) {
  [byte]($v -band 0xFF), [byte](($v -shr 8) -band 0xFF),
  [byte](($v -shr 16) -band 0xFF), [byte](($v -shr 24) -band 0xFF)
}

function New-Scaled([System.Drawing.Image]$img, [int]$w, [int]$h) {
  $bmp = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $g.Clear([System.Drawing.Color]::Transparent)
  $g.DrawImage($img, 0, 0, $w, $h)
  $g.Dispose()
  return $bmp
}

# Progressive halving before the final resize; a single bicubic step from 512 to 16
# loses too much detail and looks muddy at small sizes.
function Resize-To([System.Drawing.Image]$img, [int]$size) {
  $cur = $img
  while ($cur.Width -gt $size * 2) {
    $nw = [int][math]::Max($size, [math]::Floor($cur.Width / 2))
    $next = New-Scaled $cur $nw $nw
    if (-not [object]::ReferenceEquals($cur, $img)) { $cur.Dispose() }
    $cur = $next
  }
  $final = New-Scaled $cur $size $size
  if (-not [object]::ReferenceEquals($cur, $img)) { $cur.Dispose() }
  return $final
}

function New-DibBytes([System.Drawing.Bitmap]$bmp) {
  $w = $bmp.Width
  $h = $bmp.Height
  $rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
  $locked = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $buf = New-Object byte[] ($locked.Stride * $h)
  [System.Runtime.InteropServices.Marshal]::Copy($locked.Scan0, $buf, 0, $buf.Length)
  $bmp.UnlockBits($locked)

  $out = New-Object 'System.Collections.Generic.List[byte]'
  [void]$out.AddRange([byte[]](U32 40))            # biSize
  [void]$out.AddRange([byte[]](U32 $w))            # biWidth
  [void]$out.AddRange([byte[]](U32 ($h * 2)))      # biHeight (XOR + AND)
  [void]$out.AddRange([byte[]](U16 1))             # biPlanes
  [void]$out.AddRange([byte[]](U16 32))            # biBitCount
  [void]$out.AddRange([byte[]](U32 0))             # biCompression = BI_RGB
  [void]$out.AddRange([byte[]](U32 ($w * $h * 4)))
  [void]$out.AddRange([byte[]](U32 0))             # biXPelsPerMeter
  [void]$out.AddRange([byte[]](U32 0))             # biYPelsPerMeter
  [void]$out.AddRange([byte[]](U32 0))             # biClrUsed
  [void]$out.AddRange([byte[]](U32 0))             # biClrImportant

  for ($y = $h - 1; $y -ge 0; $y--) {              # XOR bitmap, bottom-up BGRA
    $rowStart = $y * $locked.Stride
    [void]$out.AddRange([byte[]]$buf[$rowStart..($rowStart + $w * 4 - 1)])
  }

  $maskStride = [int]([math]::Floor(($w + 31) / 32) * 4)
  [void]$out.AddRange((New-Object byte[] ($maskStride * $h)))   # AND mask, all zero

  return , $out.ToArray()
}

function Save-Png([System.Drawing.Bitmap]$bmp, [string]$path) {
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
}

$sourcePath = (Resolve-Path $Source).Path
$outPath = (Resolve-Path $OutDir).Path
$src = [System.Drawing.Image]::FromFile($sourcePath)
Write-Host "source: $sourcePath ($($src.Width)x$($src.Height))"

$sizes = @(16, 20, 24, 32, 40, 48, 64, 96, 128, 256)
$entries = @()
$pngSizes = @{ 32 = "32x32.png"; 64 = "64x64.png"; 128 = "128x128.png"; 256 = "128x128@2x.png" }

foreach ($size in $sizes) {
  $bmp = Resize-To $src $size
  if ($size -eq 256) {
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bytes = $ms.ToArray()
    $ms.Dispose()
  } else {
    $bytes = New-DibBytes $bmp
  }
  $entries += , @{ size = $size; bytes = $bytes }

  if ($pngSizes.ContainsKey($size)) {
    Save-Png $bmp (Join-Path $outPath $pngSizes[$size])
  }
  $bmp.Dispose()
}
$src.Dispose()

$count = $entries.Count
$file = New-Object 'System.Collections.Generic.List[byte]'
[void]$file.AddRange([byte[]](U16 0))      # reserved
[void]$file.AddRange([byte[]](U16 1))      # type: icon
[void]$file.AddRange([byte[]](U16 $count))

$offset = 6 + 16 * $count
foreach ($e in $entries) {
  $dim = if ($e.size -ge 256) { 0 } else { $e.size }
  [void]$file.Add([byte]$dim)
  [void]$file.Add([byte]$dim)
  [void]$file.Add([byte]0)                 # color count
  [void]$file.Add([byte]0)                 # reserved
  [void]$file.AddRange([byte[]](U16 1))    # planes
  [void]$file.AddRange([byte[]](U16 32))   # bit count
  [void]$file.AddRange([byte[]](U32 $e.bytes.Length))
  [void]$file.AddRange([byte[]](U32 $offset))
  $offset += $e.bytes.Length
}
foreach ($e in $entries) {
  [void]$file.AddRange($e.bytes)
}

$icoPath = Join-Path $outPath "icon.ico"
[System.IO.File]::WriteAllBytes($icoPath, $file.ToArray())

Write-Host "wrote: $icoPath ($count frames: $($sizes -join ', '))"
foreach ($k in ($pngSizes.Keys | Sort-Object)) {
  Write-Host "wrote: $(Join-Path $outPath $pngSizes[$k])"
}
