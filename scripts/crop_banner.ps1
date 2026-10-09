param(
  [Parameter(Mandatory=$true)][string]$Source,   # 原图（png/jpg）
  [string]$Output = ""                            # 输出路径，默认 <原名>_crop.png
)

# 裁掉图片四周的纯白/近白留白（RGB 全部 >245 视为留白）。
# 用途：横幅设计稿常自带白边，直接铺进安装器会出现"横幅和标题栏之间有缝"，
# 先用本脚本裁边再打包。依赖 System.Drawing（在 .ps1 文件内 Add-Type 不受工具沙箱拦截）。

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

if (-not $Output) {
  $Output = [System.IO.Path]::Combine(
    [System.IO.Path]::GetDirectoryName($Source),
    ([System.IO.Path]::GetFileNameWithoutExtension($Source) + "_crop.png"))
}

$bmp = New-Object System.Drawing.Bitmap($Source)
$w = $bmp.Width; $h = $bmp.Height
$top = -1; $bottom = -1; $left = $w; $right = -1

function Test-Ink($c) { -not ($c.R -gt 245 -and $c.G -gt 245 -and $c.B -gt 245) }

for ($y = 0; $y -lt $h; $y++) {
  for ($x = 0; $x -lt $w; $x += 4) {
    if (Test-Ink $bmp.GetPixel($x, $y)) {
      if ($top -lt 0) { $top = $y }
      $bottom = $y
      break
    }
  }
}
if ($top -lt 0) { throw "整张图都是留白？$Source" }

for ($x = 0; $x -lt $w; $x++) {
  for ($y = $top; $y -le $bottom; $y += 2) {
    if (Test-Ink $bmp.GetPixel($x, $y)) {
      if ($x -lt $left) { $left = $x }
      if ($x -gt $right) { $right = $x }
      break
    }
  }
}

$cw = $right - $left + 1
$ch = $bottom - $top + 1
$rect = New-Object System.Drawing.Rectangle($left, $top, $cw, $ch)
$crop = $bmp.Clone($rect, $bmp.PixelFormat)
$crop.Save($Output, [System.Drawing.Imaging.ImageFormat]::Png)
$crop.Dispose(); $bmp.Dispose()
Write-Output "src ${w}x${h} -> ${cw}x${ch} -> $Output"
