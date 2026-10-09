# 把 .ico 盖到任意 Windows PE (.exe/.dll) 的图标资源里。
# 只用 kernel32 的 BeginUpdateResource / UpdateResource / EndUpdateResource，不依赖 rcedit / Resource Hacker。
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File stamp_icon.ps1 -TargetExe "X.exe" -IcoFile "x.ico"
#
# ⚠️ 对自解压 exe 而言：UpdateResource 把 PE image size 当 EOF，会把拼接在后面的
#    payload 整段截掉。所以必须先盖在 SFX stub 副本上，再拼接 payload。

param(
  [Parameter(Mandatory=$true)][string] $TargetExe,
  [Parameter(Mandatory=$true)][string] $IcoFile,
  [uint16] $Lang = 0x409     # 资源语言 ID。MSVC/MinGW 编译的 exe 基本都是 0x409。
                             # 必须和目标里已有的一致，否则 UpdateResource 是"新增"而非"替换"，
                             # 会留下两份 RT_GROUP_ICON 导致图标不生效。
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $TargetExe)) { throw "Target exe not found: $TargetExe" }
if (-not (Test-Path -LiteralPath $IcoFile))   { throw "Icon file not found: $IcoFile" }

Add-Type -Namespace Ico -Name Res -MemberDefinition @"
[DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)]
public static extern IntPtr BeginUpdateResource(string fileName, bool deleteExisting);
[DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)]
public static extern bool UpdateResource(IntPtr hUpdate, IntPtr type, IntPtr name, ushort lang, byte[] data, uint cb);
[DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)]
public static extern bool EndUpdateResource(IntPtr hUpdate, bool discard);
"@

# ICO 布局:
#   ICONDIR { u16 reserved=0; u16 type=1; u16 count; }
#   ICONDIRENTRY[count] { u8 w,h,colors,resv; u16 planes,bpp; u32 imgSize; u32 imgOffset; }
#   imageData[count]
$ico = [System.IO.File]::ReadAllBytes($IcoFile)
$count = [BitConverter]::ToUInt16($ico, 4)
if ($count -lt 1) { throw "图标文件里没有图像: $IcoFile" }
Write-Host "ICO 含 $count 个图像"

# GRPICONDIR 与 ICONDIR 同头，但把 4 字节 offset 换成 2 字节 resource ID
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter $ms
$bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$count)

$images = @()
for ($i = 0; $i -lt $count; $i++) {
  $eo = 6 + $i * 16
  $bw.Write([byte]$ico[$eo]); $bw.Write([byte]$ico[$eo+1])
  $bw.Write([byte]$ico[$eo+2]); $bw.Write([byte]$ico[$eo+3])
  $bw.Write([UInt16]([BitConverter]::ToUInt16($ico, $eo+4)))
  $bw.Write([UInt16]([BitConverter]::ToUInt16($ico, $eo+6)))
  $sz = [BitConverter]::ToUInt32($ico, $eo+8)
  $of = [BitConverter]::ToUInt32($ico, $eo+12)
  $bw.Write([UInt32]$sz)
  $bw.Write([UInt16]($i + 1))   # 该图像的 RT_ICON resource ID
  $imgData = New-Object byte[] $sz
  [Array]::Copy($ico, $of, $imgData, 0, $sz)
  $images += , $imgData
}
$bw.Flush()
$grpData = $ms.ToArray()

$RT_ICON       = [IntPtr]3
$RT_GROUP_ICON = [IntPtr]14
$GROUP_NAME    = [IntPtr]1   # 数字 ID 1
$lang          = [UInt16]$Lang

$h = [Ico.Res]::BeginUpdateResource($TargetExe, $false)
if ($h -eq [IntPtr]::Zero) { throw "BeginUpdateResource failed ($([Runtime.InteropServices.Marshal]::GetLastWin32Error()))" }

for ($i = 0; $i -lt $count; $i++) {
  $ok = [Ico.Res]::UpdateResource($h, $RT_ICON, [IntPtr]($i + 1), $lang, $images[$i], [uint32]$images[$i].Length)
  if (-not $ok) { throw "UpdateResource RT_ICON $($i+1) failed" }
}
$ok = [Ico.Res]::UpdateResource($h, $RT_GROUP_ICON, $GROUP_NAME, $lang, $grpData, [uint32]$grpData.Length)
if (-not $ok) { throw "UpdateResource RT_GROUP_ICON failed" }

$ok = [Ico.Res]::EndUpdateResource($h, $false)
if (-not $ok) { throw "EndUpdateResource failed ($([Runtime.InteropServices.Marshal]::GetLastWin32Error()))" }

Write-Host "已把图标盖进: $TargetExe"
