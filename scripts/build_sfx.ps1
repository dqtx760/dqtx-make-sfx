<#
  build_sfx.ps1 — 用 7-Zip SFX stub 把任意文件夹打成单文件自解压 .exe

  用法:
    powershell -ExecutionPolicy Bypass -File build_sfx.ps1 -Source <文件夹> -Output <out.exe> [选项]

  常见:
    # 用例① 软件/绿色版打包 + 换图标（用系统自带 7z.sfx，零依赖）
    -Source "D:\MyApp" -Output "D:\dist\MyApp-portable.exe" -Icon "D:\MyApp\app.ico"

    # 用例② 解压后自动跑脚本（必须换 7zS.sfx / 7zSD.sfx，7z.sfx 不认 config）
    -Source "D:\theme" -Output "D:\dist\theme.exe" -Stub "D:\tools\7zS.sfx" `
      -Title "主题包" -BeginPrompt "解压并安装主题？" -Directory "theme" -RunProgram "install.cmd"

  产出的 exe: 双击 → 解压 → (可选)运行 RunProgram。
  -y 参数可静默解压，便于脚本验证。
#>
param(
  [string]$Source,                                 # 单个文件夹：其"内容"作为归档根
  [string[]]$AddItems = @(),                       # 额外顶层项（文件/文件夹），按原名字加入归档根
  [Parameter(Mandatory=$true)][string]$Output,

  [string]$Stub,                                   # SFX stub，默认 <SevenZipDir>\7z.sfx
  [string]$SevenZipDir = "C:\Program Files\7-Zip",
  [string]$Icon,                                   # 可选 .ico，会盖到 stub 副本上
  [string[]]$Exclude = @("*.bak", "*.tmp"),        # 不打包的 glob

  # —— 以下仅 7zS.sfx / 7zSD.sfx 生效；7z.sfx 会忽略 ——
  [string]$Title,
  [string]$BeginPrompt,
  [string]$Directory,
  [string]$RunProgram,
  [string]$Progress = "yes",
  [uint16]$ResLang = 0x409,                        # 图标资源语言 ID，须与目标 stub 已有的一致，否则是"新增"不是"替换"

  [switch]$KeepWork
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ---------- 0. 路径与依赖 ----------
# ---------- 0b. 归档顶层项 ----------
# -Source 的"内容"铺到归档根；-AddItems 里的每项按原名加入归档根。
$items = @()
if ($Source) {
  $src = (Resolve-Path -LiteralPath $Source).Path
  if (-not (Test-Path -LiteralPath $src -PathType Container)) { throw "Source 不是文件夹: $src" }
  $items += "$src\*"
}
foreach ($it in $AddItems) {
  $rp = (Resolve-Path -LiteralPath $it).Path
  $items += $rp
}
if ($items.Count -eq 0) { throw "必须提供 -Source 或 -AddItems 至少一个" }

$SevenZipDir = $SevenZipDir.TrimEnd("\")
$sevenZip = Join-Path $SevenZipDir "7z.exe"

# ---------- 0a. 默认值（sfx-defaults.txt 与脚本同目录，UTF-8 带 BOM）----------
# 未在命令行指定的参数从这里取，方便把常用图标 / stub 固化下来。
$defaultsFile = Join-Path $PSScriptRoot "sfx-defaults.txt"
if (Test-Path -LiteralPath $defaultsFile) {
  foreach ($line in Get-Content -LiteralPath $defaultsFile -Encoding UTF8) {
    if ($line -match '^\s*#') { continue }
    if ($line -match '^\s*Icon\s*=\s*(.+?)\s*$' -and -not $Icon)   { $Icon = $Matches[1] }
    if ($line -match '^\s*Stub\s*=\s*(.+?)\s*$' -and -not $Stub)   { $Stub = $Matches[1] }
  }
  if ($Icon) { Write-Host "icon     : 使用默认 $Icon" }
  if ($Stub) { Write-Host "stub     : 使用默认 $Stub" }
}

if (-not $Stub) { $Stub = Join-Path $SevenZipDir "7z.sfx" }

foreach ($p in @($sevenZip, $Stub)) {
  if (-not (Test-Path -LiteralPath $p)) { throw "找不到: $p" }
}

$outFull = [System.IO.Path]::GetFullPath($Output)
$outDir = Split-Path -Parent $outFull
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

# ---------- 1. stub 能力检测 ----------
# 实测结论: Program Files 自带的 7z.sfx / 7zCon.sfx 完全不读 config.txt。
# 只有 7zS.sfx / 7zSD.sfx (modSFX) 才认 Title/BeginPrompt/Directory/RunProgram 等键。
$stubName = [System.IO.Path]::GetFileName($Stub).ToLowerInvariant()
$stubReadsConfig = ($stubName -ne "7z.sfx" -and $stubName -ne "7zcon.sfx")

$wantConfig = $PSBoundParameters.ContainsKey("Title") -or
              $PSBoundParameters.ContainsKey("BeginPrompt") -or
              $PSBoundParameters.ContainsKey("Directory") -or
              $PSBoundParameters.ContainsKey("RunProgram")

Write-Host "SFX stub : $Stub ($((Get-Item -LiteralPath $Stub).Length) bytes)"
if (-not $stubReadsConfig) {
  Write-Host "  能力: 不读 config.txt — 解压到 exe 所在目录，用户可在标准解压对话框里改目标目录"
  if ($wantConfig) {
    Write-Warning "你传了 Title/BeginPrompt/Directory/RunProgram，但 $stubName 会忽略它们。"
    Write-Warning "需要这些功能请改用 7zS.sfx 或 7zSD.sfx（用 -Stub 指定）。"
  }
} else {
  if (-not $wantConfig) { Write-Warning "$stubName 支持 config，但你一个 config 参数都没传，将不生成 config.txt。" }
  else { Write-Host "  能力: 支持 config.txt — 解压到 %TEMP% 后运行 RunProgram，退出后清理" }
}

# ---------- 2. 工作目录 ----------
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("sfxbuild_" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $work -Force | Out-Null
Write-Host "工作目录 : $work"

try {
  # ---------- 3. 压缩 payload ----------
  $payload = Join-Path $work "payload.7z"
  $sevenZipArgs = @("a", "-t7z", "-m0=lzma2", "-mx=9", "-ms=on", "-mfb=64", "-md=64m", "-mqs=on", "-mmt=on", $payload) + $items
  foreach ($e in $Exclude) { $sevenZipArgs += "-xr!$e" }

  $out7z = & $sevenZip @sevenZipArgs 2>&1
  if ($LASTEXITCODE -ne 0) { $out7z | ForEach-Object { Write-Host "  $_" }; throw "7z 压缩失败 (exit $LASTEXITCODE)" }
  Write-Host ("payload  : {0:N2} MB" -f ((Get-Item -LiteralPath $payload).Length / 1MB))

  # ---------- 4. config.txt (UTF-8 BOM + CRLF) ----------
  $parts = @()
  if ($stubReadsConfig -and $wantConfig) {
    $config = Join-Path $work "config.txt"
    $lines = @(";!@Install@!UTF-8!")
    if ($PSBoundParameters.ContainsKey("Title"))       { $lines += "Title=`"$Title`"" }
    if ($PSBoundParameters.ContainsKey("BeginPrompt")) { $lines += "BeginPrompt=`"$BeginPrompt`"" }
    if ($PSBoundParameters.ContainsKey("Directory"))   { $lines += "Directory=`"$Directory`"" }
    if ($PSBoundParameters.ContainsKey("RunProgram"))  { $lines += "RunProgram=`"$RunProgram`"" }
    $lines += "Progress=`"$Progress`""
    $lines += ";!@InstallEnd@!"

    $crlf = ($lines -join "`r`n") + "`r`n"
    $bom = [byte[]](0xEF, 0xBB, 0xBF)
    [System.IO.File]::WriteAllBytes($config, $bom + [System.Text.Encoding]::UTF8.GetBytes($crlf))
    $parts += $config
    Write-Host "config   : 已生成 (UTF-8 BOM + CRLF)"
  }

  # ---------- 5. stub 副本 + 图标 ----------
  $stubUse = $Stub
  if ($Icon) {
    if (-not (Test-Path -LiteralPath $Icon)) { throw "找不到图标: $Icon" }
    $stubUse = Join-Path $work "stub-stamped.sfx"
    Copy-Item -LiteralPath $Stub -Destination $stubUse -Force

    # 注意: 必须在 concat 之前盖章。UpdateResource 把 PE image size 当 EOF，会对已拼接
    # 的 exe 截断掉 appended overlay。
    Add-Type -Namespace Sfx -Name Res -MemberDefinition @"
[DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)]
public static extern IntPtr BeginUpdateResource(string fileName, bool deleteExisting);
[DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)]
public static extern bool UpdateResource(IntPtr hUpdate, IntPtr type, IntPtr name, ushort lang, byte[] data, uint cb);
[DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)]
public static extern bool EndUpdateResource(IntPtr hUpdate, bool discard);
"@
    $ico = [System.IO.File]::ReadAllBytes($Icon)
    $count = [BitConverter]::ToUInt16($ico, 4)
    if ($count -lt 1) { throw "图标文件没有图像: $Icon" }

    # GRPICONDIR: 与 ICONDIR 同头，但把 4 字节 offset 换成 2 字节 resource ID
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
      $bw.Write([UInt16]($i + 1))
      $d = New-Object byte[] $sz
      [Array]::Copy($ico, $of, $d, 0, $sz)
      $images += , $d
    }
    $bw.Flush()
    $grp = $ms.ToArray()

    $h = [Sfx.Res]::BeginUpdateResource($stubUse, $false)
    if ($h -eq [IntPtr]::Zero) { throw "BeginUpdateResource 失败" }
    for ($i = 0; $i -lt $count; $i++) {
      [void][Sfx.Res]::UpdateResource($h, [IntPtr]3, [IntPtr]($i + 1), [UInt16]$ResLang, $images[$i], [uint32]$images[$i].Length)
    }
    [void][Sfx.Res]::UpdateResource($h, [IntPtr]14, [IntPtr]1, [UInt16]$ResLang, $grp, [uint32]$grp.Length)
    if (-not [Sfx.Res]::EndUpdateResource($h, $false)) { throw "EndUpdateResource 失败" }
    Write-Host "icon     : 已盖到 stub 副本 ($((Get-Item -LiteralPath $stubUse).Length) bytes)"
  }

  # ---------- 6. 拼接 stub + config + payload ----------
  # 流式写入，避免大 payload 全量读进内存
  $dest = [System.IO.File]::Create($outFull)
  try {
    foreach ($f in (@($stubUse) + $parts + @($payload))) {
      $in = [System.IO.File]::OpenRead($f)
      try { $in.CopyTo($dest) } finally { $in.Dispose() }
    }
  } finally { $dest.Dispose() }

  $o = Get-Item -LiteralPath $outFull
  Write-Host ""
  Write-Host "完成: $($o.FullName)"
  Write-Host ("  大小   : {0:N0} bytes ({1:N2} MB)" -f $o.Length, ($o.Length / 1MB))
  Write-Host ("  SHA256 : {0}" -f (Get-FileHash -LiteralPath $outFull -Algorithm SHA256).Hash)
} finally {
  if ($KeepWork) { Write-Host "中间文件保留: $work" }
  elseif (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}
