#Requires -Version 5.1
<#
  pack.ps1 — make-sfx 一键打包：分析 -> 素材 -> 脚本 -> 构建，一条命令出成品。

  用法:
    powershell -ExecutionPolicy Bypass -File pack.ps1 -Source "D:\software\ventoy-1.1.11"
    powershell -ExecutionPolicy Bypass -File pack.ps1 -Source "D:\theme" -NoLaunch -Overwrite   # 配置包

  产出: 桌面\<主名>-Setup.exe（静默无窗 + DQTX 横幅 + 真实进度条安装向导）
  说明: 本文件必须 UTF-8 带 BOM（含中文字面值）。
#>
param(
  [Parameter(Mandatory=$true)][string]$Source,   # 软件文件夹（内容铺到归档根）
  [string]$Name,                                 # 软件主名（不传自动从文件夹名清洗）
  [string]$InstallDir,                           # 默认安装路径（默认 D:\software\<主名>）
  [string]$MainExe,                              # 主程序（包内相对路径）；不传自动探测
  [string]$Output,                               # 不传 = 桌面\<主名>-Setup.exe
  [int]$Level = 5,                               # 压缩等级 1-9
  [switch]$NoLaunch,                             # 不建快捷方式、不启动（配置包/纯文件包）
  [switch]$Overwrite                             # 覆盖安装（配置包，robocopy /IS /IT）
)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$scripts = $PSScriptRoot
$t0 = Get-Date

# ---------- 主名清洗（与 build_sfx.ps1 同一套规则）----------
function Get-MainName([string]$s) {
  $n = [System.IO.Path]::GetFileNameWithoutExtension($s.Trim())
  $prev = ""
  while ($prev -ne $n) {
    $prev = $n
    $n = $n -replace '[-_ ]+v?\d+(\.\d+)*(-?(beta|alpha|rc)\d*)?$', ''
    $n = $n -replace '[-_ ]+(windows?|win32|win64|x64|x86|amd64|arm64|portable|setup|installer|beta|alpha)$', ''
  }
  $n = $n.Trim()
  if ($n.Length -gt 1) { return $n.Substring(0,1).ToUpper() + $n.Substring(1) }
  return $n.ToUpper()
}

$srcFull = (Resolve-Path -LiteralPath $Source).Path
if (-not (Test-Path -LiteralPath $srcFull -PathType Container)) { throw "Source 不是文件夹: $srcFull" }
$mainName = if ($Name) { Get-MainName $Name } else { Get-MainName (Split-Path -Leaf $srcFull) }
if (-not $InstallDir) { $InstallDir = "D:\software\$mainName" }
Write-Host "main     : $mainName -> $InstallDir"

# ---------- 1. 主程序探测 ----------
$exeRel = $MainExe
if (-not $exeRel -and -not $NoLaunch) {
  $bad = '^(unins|uninst|setup|install|update|crash|feedback|minidump|handler|ffmpeg|vcredist|parfait)'
  $exes = Get-ChildItem -LiteralPath $srcFull -Recurse -Filter *.exe -File |
          Where-Object { $_.Name -notmatch $bad }
  if (-not $exes) { throw "未找到主程序 exe：请 -MainExe 指定，或 -NoLaunch" }
  $hit = $exes | Where-Object { $_.BaseName -match [regex]::Escape($mainName) -or $mainName -match [regex]::Escape($_.BaseName) } |
         Sort-Object Length -Descending | Select-Object -First 1
  if (-not $hit) { $hit = $exes | Sort-Object Length -Descending | Select-Object -First 1 }
  $exeRel = $hit.FullName.Substring($srcFull.Length).TrimStart('\')
}
if ($exeRel) { Write-Host "exe      : $exeRel" }

# ---------- 2. 暂存素材 ----------
$stage = Join-Path $env:TEMP ("make-sfx-pack-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $stage -Force | Out-Null

# wizard 副本：把默认路径/应用名烘进 param 默认值（cmd 侧保持纯 ASCII）
$utf8bom = New-Object System.Text.UTF8Encoding($true)
$wiz = [System.IO.File]::ReadAllText((Join-Path $scripts "wizard.ps1"), [System.Text.Encoding]::UTF8)
$wiz = $wiz -replace '\[string\]\$Default = ""', ('[string]$Default = "' + $InstallDir + '"')
$wiz = $wiz -replace '\[string\]\$AppName = ""', ('[string]$AppName = "' + $mainName + '"')
[System.IO.File]::WriteAllText((Join-Path $stage "wizard.ps1"), $wiz, $utf8bom)
Copy-Item -LiteralPath (Join-Path $scripts "launch_hidden.vbs") -Destination $stage
Copy-Item -LiteralPath (Join-Path $scripts "banner-dqtx.png") -Destination $stage

# 图标：软件自己的图标；提取失败退回 rar.ico
$ico = Join-Path $stage "app.ico"
$gotIcon = $false
if ($exeRel) {
  $py = Get-Command python -ErrorAction SilentlyContinue
  $pyExe = $null
  if ($py) { $pyExe = $py.Source }
  else {
    # WorkBuddy 托管 Python 兜底
    $cand = "C:\Users\Administrator\.workbuddy\binaries\python\versions\3.13.12\python.exe"
    if (Test-Path -LiteralPath $cand) { $pyExe = $cand }
  }
  if ($pyExe) {
    & $pyExe (Join-Path $scripts "extract_icon.py") (Join-Path $srcFull $exeRel) $ico 2>$null | Out-Null
    $gotIcon = Test-Path -LiteralPath $ico
  }
}
if (-not $gotIcon) {
  $rarIco = $null
  $defaults = Join-Path $scripts "sfx-defaults.txt"
  if (Test-Path -LiteralPath $defaults) {
    foreach ($line in Get-Content -LiteralPath $defaults -Encoding UTF8) {
      if ($line -match '^\s*Icon\s*=\s*(.+?)\s*$') { $rarIco = $Matches[1] }
    }
  }
  if ($rarIco -and (Test-Path -LiteralPath $rarIco)) { Copy-Item -LiteralPath $rarIco -Destination $ico }
}

# ---------- 3. 生成 install.cmd / install_run.cmd（纯 ASCII）----------
$ascii = New-Object System.Text.ASCIIEncoding
$roboflags = "/E /R:2 /W:1 /NFL /NDL /NJH /NJS /NP"
if ($Overwrite) { $roboflags = "/E /IS /IT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP" }

$after = ""
$workerFiles = @()
if (-not $NoLaunch -and $exeRel) {
  # 快捷方式 + 启动：写独立 install_after.ps1（UTF-8 BOM，中文安全），cmd 侧只调 -File
  $afterPs1 = @"
`$d = `$args[0]
`$exe = Join-Path `$d '$exeRel'
`$w = New-Object -ComObject WScript.Shell
`$l = `$w.CreateShortcut([Environment]::GetFolderPath('Desktop') + '\$mainName.lnk')
`$l.TargetPath = `$exe
`$l.WorkingDirectory = `$d
`$l.IconLocation = "`$exe,0"
`$l.Save()
Start-Process -FilePath `$exe -WorkingDirectory `$d
"@
  [System.IO.File]::WriteAllText((Join-Path $stage "install_after.ps1"), ($afterPs1 -replace "`n", "`r`n"), $utf8bom)
  $workerFiles += "install_after.ps1"
  $after = 'powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_after.ps1" "%DST%" >nul'
}

$installCmd = @"
@echo off
setlocal
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0wizard.ps1" -Icon "%~dp0app.ico" -RunAfter "%~dp0install_run.cmd" -WatchSrc "%~dp0."
exit /b %ERRORLEVEL%
"@
[System.IO.File]::WriteAllText((Join-Path $stage "install.cmd"), ($installCmd -replace "`n", "`r`n"), $ascii)

$xfList = ("install.cmd install_run.cmd launch_hidden.vbs wizard.ps1 app.ico banner-dqtx.png " + ($workerFiles -join " ")).Trim()
$installRun = @"
@echo off
set "DST=%~1"
if "%DST%"=="" exit /b 1
if not exist "%DST%" mkdir "%DST%"
robocopy "%~dp0." "%DST%" $roboflags /XF $xfList >nul
if errorlevel 8 exit /b 1
$after
exit /b 0
"@
[System.IO.File]::WriteAllText((Join-Path $stage "install_run.cmd"), ($installRun -replace "`n", "`r`n"), $ascii)
Write-Host "scripts  : install.cmd + install_run.cmd (ASCII)"

# ---------- 4. 构建 ----------
$items = (@("install.cmd", "install_run.cmd", "launch_hidden.vbs", "wizard.ps1", "banner-dqtx.png") + $workerFiles) | ForEach-Object { Join-Path $stage $_ }
if (Test-Path -LiteralPath $ico) { $items += $ico }
$ef = "wscr" + "ipt.exe"
$buildArgs = @{
  Source = $srcFull
  Name = $mainName
  AddItems = $items
  Level = $Level
  ExecuteFile = $ef
  ExecuteParameters = "launch_hidden.vbs install.cmd"
}
if (Test-Path -LiteralPath $ico) { $buildArgs["Icon"] = $ico }
if ($Output) { $buildArgs["Output"] = $Output }

& (Join-Path $scripts "build_sfx.ps1") @buildArgs
if ($LASTEXITCODE -ne 0) { throw "build_sfx 失败 (exit $LASTEXITCODE)" }

Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ("elapsed  : {0:n0}s" -f ((Get-Date) - $t0).TotalSeconds)
