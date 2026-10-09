param(
  [string]$Default = "",        # 输入框默认路径（建议 "D:\software\MyApp"）
  [string]$AppName = "",        # 应用名。提供后：文案自动带应用名；浏览选中后自动加 \AppName 子文件夹
  [string]$Title   = "安装程序",
  [string]$Icon    = "rar.ico",  # 左上角/任务栏图标，默认取脚本同目录的 rar.ico（WinRAR 图标，固定标准）
  [string]$Banner  = "",        # 横幅图片路径；不传或文件不存在时回退到 DQTX 标准横幅
  [string]$Tagline = "安全 · 绿色 · 纯净",
  [string]$RunAfter = "",       # 可选：点开始安装后由向导调起的安装脚本（%1=目标路径），向导切换"数据解压中"进度视图并等待完成
  [string]$WatchSrc = ""        # 可选：被复制的源文件夹（如 %~dp0app）。提供后进度条按"已复制字节/源总字节"真实推进（从左走到右）
)

# 现代扁平风格安装向导（无边框自绘标题栏 + 横幅 + 路径选择），替代 7zSD 丑陋的 BeginPrompt。
# 用法：install.cmd 里 for /f 捕获 stdout（powershell 必须带 -STA）：
#   for /f "usebackq delims=" %%i in (`powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0wizard.ps1" -Default "%DEFAULT%" -AppName "MyApp" -Icon "%~dp0app.ico" -Banner "%~dp0banner.png"`) do set "DST=%%i"
# 「取消 / ✕」→ exit 1 → DST 未定义。stdout 只打印最终路径一行。
# 注意：本文件必须存成 UTF-8 **带 BOM**；cmd 调用方保持纯 ASCII，中文默认值烘在本文件里。

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()   # Marquee 进度条需要视觉样式

# ---- 默认横幅：未传 -Banner 时回退到 DQTX 标准横幅（头像+公众号+官网，固定标准）----
if (-not $Banner -or -not (Test-Path -LiteralPath $Banner)) {
  $stdBanner = Join-Path $PSScriptRoot "banner-dqtx.png"                # 打包时随脚本拷到同目录
  if (-not (Test-Path -LiteralPath $stdBanner)) {
    $stdBanner = Join-Path (Split-Path $PSScriptRoot -Parent) "assets\banner-dqtx.png"  # skill 中央位置
  }
  if (Test-Path -LiteralPath $stdBanner) { $Banner = $stdBanner }
}

# ---- 主题色 ----
$C_BLUE   = [System.Drawing.Color]::FromArgb(37, 99, 235)    # 主蓝 #2563EB
$C_BLUE_L = [System.Drawing.Color]::FromArgb(191, 219, 254)  # 输入框描边 #BFDBFE
$C_DARK   = [System.Drawing.Color]::FromArgb(31, 41, 55)     # 标题 #1F2937
$C_GRAY   = [System.Drawing.Color]::FromArgb(107, 114, 128)  # 次要文字 #6B7280
$C_GRAY_D = [System.Drawing.Color]::FromArgb(55, 65, 81)     # 标签 #374151
$C_LINE   = [System.Drawing.Color]::FromArgb(209, 213, 219)  # 描边 #D1D5DB
$C_HOVER  = [System.Drawing.Color]::FromArgb(229, 231, 235)  # 标题栏按钮悬停 #E5E7EB

# ---- 无边框拖动 + 控制台隐藏 P/Invoke ----
Add-Type -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ReleaseCapture();
[DllImport("user32.dll")] public static extern int SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@ -Name U32 -Namespace Wiz | Out-Null

# 弹向导期间隐藏宿主控制台（install.cmd 的黑窗），确认安装后再唤回显示复制进度
$hwndConsole = [Wiz.U32]::GetConsoleWindow()
if ($hwndConsole -ne [IntPtr]::Zero) { [void][Wiz.U32]::ShowWindow($hwndConsole, 0) }   # SW_HIDE

# ---- 圆角路径 ----
function New-RoundPath([float]$w, [float]$h, [float]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = 2 * $r
  $p.AddArc(0, 0, $d, $d, 180, 90)
  $p.AddArc(($w - $d), 0, $d, $d, 270, 90)
  $p.AddArc(($w - $d), ($h - $d), $d, $d, 0, 90)
  $p.AddArc(0, ($h - $d), $d, $d, 90, 90)
  $p.CloseFigure()
  return $p
}

# ---- 布局常量（先算好，New-Object 里不做算术）----
$W = 680
$H_TITLE = 44
$H_BANNER = 148            # 2172x472（已裁白边）按 680 宽等比
$Y_BODY = $H_TITLE + $H_BANNER   # 192
$Y_TITLE2 = $Y_BODY + 10
$Y_SUB = $Y_BODY + 42
$Y_CAP = $Y_BODY + 74
$Y_FIELD = $Y_BODY + 96
$H_FIELD = 34
$Y_BTN = $Y_BODY + 144
$H_BTN = 40
$H_FORM = $Y_BTN + $H_BTN + 20

$form                 = New-Object System.Windows.Forms.Form
$form.Text            = $Title
$form.ClientSize      = New-Object System.Drawing.Size($W, $H_FORM)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition   = "CenterScreen"
$form.MaximizeBox     = $false
$form.TopMost         = $true
$form.ShowInTaskbar   = $true
$form.BackColor       = [System.Drawing.Color]::White
if ($Icon -and (Test-Path -LiteralPath $Icon)) {
  try { $form.Icon = New-Object System.Drawing.Icon($Icon) } catch {}
}
$form.Region = New-Object System.Drawing.Region((New-RoundPath $W $H_FORM 12))

# ---- 生成应用徽章图标（蓝底圆角方块 + 白色 R）----
function New-AppBadge([int]$size) {
  $bmp = New-Object System.Drawing.Bitmap($size, $size)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.Clear([System.Drawing.Color]::Transparent)
  $r = [Math]::Max(6, [int]($size * 0.22))
  $brush = New-Object System.Drawing.SolidBrush($C_BLUE)
  $g.FillPath($brush, (New-RoundPath $size $size $r))
  $fsize = $size * 0.52
  $font = New-Object System.Drawing.Font("Segoe UI", $fsize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
  $fmt = New-Object System.Drawing.StringFormat
  $fmt.Alignment = [System.Drawing.StringAlignment]::Center
  $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
  $whiteB = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
  $rect = New-Object System.Drawing.RectangleF(0, ($size * 0.04), $size, $size)
  $g.DrawString("R", $font, $whiteB, $rect, $fmt)
  $g.Dispose()
  return $bmp
}

# ---- 生成蓝色小文件夹图标 ----
function New-FolderIcon([int]$w, [int]$h) {
  $bmp = New-Object System.Drawing.Bitmap($w, $h)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.Clear([System.Drawing.Color]::Transparent)
  $brush = New-Object System.Drawing.SolidBrush($C_BLUE)
  $tabW = [int]($w * 0.42); $tabH = [int]($h * 0.28); $bodyY = [int]($h * 0.30)
  $g.FillPath($brush, (New-RoundPath $tabW $tabH 2))
  $g.FillPath($brush, (New-RoundPath $w ($h - $bodyY) 3))
  $g.Dispose()
  return $bmp
}

# ---- 生成对勾小图标（绿圈白勾）----
function New-CheckIcon([int]$s) {
  $bmp = New-Object System.Drawing.Bitmap($s, $s)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.Clear([System.Drawing.Color]::Transparent)
  $green = [System.Drawing.Color]::FromArgb(22, 163, 74)
  $fill = New-Object System.Drawing.SolidBrush($green)
  $g.FillEllipse($fill, 0, 0, ($s - 1), ($s - 1))
  $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, [float]($s * 0.14))
  $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $g.DrawLine($pen, [int]($s * 0.26), [int]($s * 0.52), [int]($s * 0.42), [int]($s * 0.72))
  $g.DrawLine($pen, [int]($s * 0.42), [int]($s * 0.72), [int]($s * 0.76), [int]($s * 0.28))
  $g.Dispose()
  return $bmp
}

# ---- 标题栏 ----
$titlePanel = New-Object System.Windows.Forms.Panel
$titlePanel.Location = New-Object System.Drawing.Point(0, 0)
$titlePanel.Size = New-Object System.Drawing.Size($W, $H_TITLE)
$titlePanel.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($titlePanel)

$titleIconPb = New-Object System.Windows.Forms.PictureBox
# 左上角图标：优先用打包进来的 .ico（rar.ico），没有则退回蓝色 R 徽章
$titleImg = $null
if ($Icon) {
  $iconPath = $Icon
  if (-not [System.IO.Path]::IsPathRooted($iconPath)) {
    $cand = Join-Path $PSScriptRoot $iconPath
    if (Test-Path -LiteralPath $cand) { $iconPath = $cand }
  }
  if (Test-Path -LiteralPath $iconPath) {
    try { $titleImg = (New-Object System.Drawing.Icon($iconPath)).ToBitmap() } catch {}
  }
}
if (-not $titleImg) { $titleImg = (New-AppBadge 20) }
$titleIconPb.Image = $titleImg
$titleIconPb.Location = New-Object System.Drawing.Point(14, 12)
$titleIconPb.Size = New-Object System.Drawing.Size(20, 20)
$titleIconPb.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$titlePanel.Controls.Add($titleIconPb)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = $Title
$titleLabel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9.75)
$titleLabel.ForeColor = $C_DARK
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object System.Drawing.Point(42, 13)
$titlePanel.Controls.Add($titleLabel)

$btnMin = New-Object System.Windows.Forms.Button
$btnMin.Text = "—"
$btnMin.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnMin.FlatAppearance.BorderSize = 0
$btnMin.ForeColor = $C_GRAY
$btnMin.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$btnMin.Location = New-Object System.Drawing.Point(($W - 88), 0)
$btnMin.Size = New-Object System.Drawing.Size(44, $H_TITLE)
$titlePanel.Controls.Add($btnMin)

$btnX = New-Object System.Windows.Forms.Button
$btnX.Text = "✕"
$btnX.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnX.FlatAppearance.BorderSize = 0
$btnX.ForeColor = $C_GRAY
$btnX.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$btnX.Location = New-Object System.Drawing.Point(($W - 44), 0)
$btnX.Size = New-Object System.Drawing.Size(44, $H_TITLE)
$titlePanel.Controls.Add($btnX)

$btnMin.Add_Click({ $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized })
$btnMin.Add_MouseEnter({ $btnMin.BackColor = $C_HOVER })
$btnMin.Add_MouseLeave({ $btnMin.BackColor = [System.Drawing.Color]::White })
$btnX.Add_Click({ $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $form.Close() })
$btnX.Add_MouseEnter({ $btnX.BackColor = $C_HOVER })
$btnX.Add_MouseLeave({ $btnX.BackColor = [System.Drawing.Color]::White })

# 标题栏整体可拖动
$titleDrag = {
  if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
    [void][Wiz.U32]::ReleaseCapture()
    [void][Wiz.U32]::SendMessage($form.Handle, 0xA1, 0x2, 0)
  }
}
$titlePanel.Add_MouseDown($titleDrag)
$titleLabel.Add_MouseDown($titleDrag)
$titleIconPb.Add_MouseDown($titleDrag)

# ---- 横幅 ----
if ($Banner -and (Test-Path -LiteralPath $Banner)) {
  $pic = New-Object System.Windows.Forms.PictureBox
  $pic.Image = [System.Drawing.Image]::FromFile($Banner)
  $pic.Location = New-Object System.Drawing.Point(0, $H_TITLE)
  $pic.Size = New-Object System.Drawing.Size($W, $H_BANNER)
  $pic.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
  $pic.Add_MouseDown($titleDrag)
  $form.Controls.Add($pic)
}

# ---- 主文案 ----
$appLabel = if ($AppName) { $AppName } else { "应用" }
$lblT1 = New-Object System.Windows.Forms.Label
$lblT1.Text = "即将安装 "
$lblT1.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 13.5, [System.Drawing.FontStyle]::Bold)
$lblT1.ForeColor = $C_DARK
$lblT1.AutoSize = $true
$lblT1.Location = New-Object System.Drawing.Point(24, $Y_TITLE2)
$form.Controls.Add($lblT1)

$lblT2 = New-Object System.Windows.Forms.Label
$lblT2.Text = $appLabel
$lblT2.Font = $lblT1.Font
$lblT2.ForeColor = $C_BLUE
$lblT2.AutoSize = $true
$lblT2.Location = New-Object System.Drawing.Point((24 + $lblT1.PreferredWidth), $Y_TITLE2)
$form.Controls.Add($lblT2)

$lblD = New-Object System.Windows.Forms.Label
$lblD.Text = "本程序将为您解压并安装 $appLabel 到指定位置。"
$lblD.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$lblD.ForeColor = $C_GRAY
$lblD.AutoSize = $true
$lblD.Location = New-Object System.Drawing.Point(25, $Y_SUB)
$form.Controls.Add($lblD)

# ---- 路径区 ----
$lblCap = New-Object System.Windows.Forms.Label
$lblCap.Text = "安装到以下位置："
$lblCap.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$lblCap.ForeColor = $C_GRAY_D
$lblCap.AutoSize = $true
$lblCap.Location = New-Object System.Drawing.Point(24, $Y_CAP)
$form.Controls.Add($lblCap)

$fieldPanel = New-Object System.Windows.Forms.Panel
$fieldPanel.Location = New-Object System.Drawing.Point(24, $Y_FIELD)
$fieldPanel.Size = New-Object System.Drawing.Size(522, $H_FIELD)
$fieldPanel.BackColor = [System.Drawing.Color]::White
$fieldPanel.Add_Paint({
  param($s, $e)
  $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $pen = New-Object System.Drawing.Pen($C_BLUE_L, 1.6)
  $e.Graphics.DrawPath($pen, (New-RoundPath $fieldPanel.Width $fieldPanel.Height 8))
})
$form.Controls.Add($fieldPanel)

$txt = New-Object System.Windows.Forms.TextBox
$txt.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$txt.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)
$txt.ForeColor = $C_DARK
$txt.Location = New-Object System.Drawing.Point(14, 9)
$txt.Size = New-Object System.Drawing.Size(498, 18)
$txt.Text = $Default
$fieldPanel.Controls.Add($txt)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "浏览..."
$btnBrowse.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBrowse.FlatAppearance.BorderSize = 0
$btnBrowse.BackColor = [System.Drawing.Color]::FromArgb(243, 244, 246)
$btnBrowse.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$btnBrowse.ForeColor = $C_GRAY_D
$btnBrowse.Location = New-Object System.Drawing.Point(556, $Y_FIELD)
$btnBrowse.Size = New-Object System.Drawing.Size(100, $H_FIELD)
$btnBrowse.Region = New-Object System.Drawing.Region((New-RoundPath 100 $H_FIELD 8))
$btnBrowse.Add_Click({
  $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
  $fbd.ShowNewFolderButton = $true
  if ($AppName) { $fbd.Description = "选择安装位置（将在其中创建 $AppName 子文件夹）" }
  else          { $fbd.Description = "选择安装位置" }
  if ($fbd.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
    if ($AppName) { $txt.Text = Join-Path $fbd.SelectedPath $AppName }
    else          { $txt.Text = $fbd.SelectedPath }
  }
})
$form.Controls.Add($btnBrowse)

# ---- 进度视图（点开始安装后切换；初始隐藏）----
function Get-FolderBytes([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return 0L }
  $sum = 0L
  foreach ($f in [System.IO.Directory]::EnumerateFiles($path, "*", [System.IO.SearchOption]::AllDirectories)) {
    try { $sum += (New-Object System.IO.FileInfo($f)).Length } catch {}
  }
  return $sum
}

$yProg = $Y_CAP + 34
$progBar = New-Object System.Windows.Forms.ProgressBar
$progBar.Minimum = 0
$progBar.Maximum = 100
$progBar.Value = 0
$progBar.Location = New-Object System.Drawing.Point(24, $yProg)
$progBar.Size = New-Object System.Drawing.Size(632, 10)
$progBar.Visible = $false
$form.Controls.Add($progBar)

$script:doneReady = $false
$script:runExit = 0
$script:dstPath = ""
$script:totalBytes = 0L
$script:initBytes = 0L
$script:shownPct = 0
$script:closeTicks = 0

# ---- 底部：标签 + 按钮 ----
$checkPb = New-Object System.Windows.Forms.PictureBox
$checkPb.Image = (New-CheckIcon 18)
$checkPb.Location = New-Object System.Drawing.Point(24, ($Y_BTN + 11))
$checkPb.Size = New-Object System.Drawing.Size(18, 18)
$checkPb.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$form.Controls.Add($checkPb)

$lblTag = New-Object System.Windows.Forms.Label
$lblTag.Text = $Tagline
$lblTag.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$lblTag.ForeColor = $C_GRAY
$lblTag.AutoSize = $true
$lblTag.Location = New-Object System.Drawing.Point(48, ($Y_BTN + 12))
$form.Controls.Add($lblTag)

$btnOk = New-Object System.Windows.Forms.Button
$btnOk.Text = "开始安装  →"
$btnOk.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOk.FlatAppearance.BorderSize = 0
$btnOk.BackColor = $C_BLUE
$btnOk.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9.75, [System.Drawing.FontStyle]::Bold)
$btnOk.ForeColor = [System.Drawing.Color]::White
$btnOk.Location = New-Object System.Drawing.Point(446, $Y_BTN)
$btnOk.Size = New-Object System.Drawing.Size(128, $H_BTN)
$btnOk.Region = New-Object System.Drawing.Region((New-RoundPath 128 $H_BTN 10))
$btnOk.Add_Click({
  # 安装完成/失败后的"完成/关闭"按钮
  if ($script:doneReady) {
    if ($script:runExit -eq 0) { $form.DialogResult = [System.Windows.Forms.DialogResult]::OK }
    else                       { $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel }
    $form.Close()
    return
  }
  $p = $txt.Text.Trim()
  if ([string]::IsNullOrWhiteSpace($p)) { return }
  # UNC 路径跳过盘符检查
  if ($p -notmatch '^[\\/][\\/]') {
    $drive = $p.Substring(0, 2)
    if (-not (Test-Path "$drive\")) {
      [void][System.Windows.Forms.MessageBox]::Show($form, "找不到磁盘 $drive\ ，请换一个位置。", "位置无效",
        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
      return
    }
  }
  if ($RunAfter) {
    # —— 切换"数据解压中"进度视图：向导调起安装脚本并等待 ——
    $script:dstPath = $p
    $titleLabel.Text = "数据解压中"
    $lblT1.Text = "正在安装 "
    $lblD.Text = "数据解压中，请稍候…"
    $lblCap.Visible = $false; $fieldPanel.Visible = $false; $btnBrowse.Visible = $false
    $checkPb.Visible = $false; $lblTag.Visible = $false
    $btnOk.Visible = $false; $btnCancel.Visible = $false
    $progBar.Value = 0
    $progBar.Visible = $true

    # 真实进度：源总字节 vs 目标目录新增字节（重装时先扣掉已有字节）
    if ($WatchSrc -and (Test-Path -LiteralPath $WatchSrc)) {
      $script:totalBytes = Get-FolderBytes $WatchSrc
      $script:initBytes = Get-FolderBytes $script:dstPath
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = '/c ""' + $RunAfter + '" "' + $script:dstPath + '""'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $script:procRun = [System.Diagnostics.Process]::Start($psi)

    $script:runTimer = New-Object System.Windows.Forms.Timer
    $script:runTimer.Interval = 200
    $script:runTimer.Add_Tick({
      # 100% 稍停后自动关窗（主程序由安装脚本 start 拉起）
      if ($script:closeTicks -gt 0) {
        $script:closeTicks--
        if ($script:closeTicks -eq 0) {
          $script:runTimer.Stop()
          $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
          $form.Close()
        }
        return
      }
      if ($script:procRun.HasExited) {
        $script:runExit = $script:procRun.ExitCode
        $script:procRun.Dispose()
        if ($script:runExit -eq 0) {
          $progBar.Value = 100
          $script:closeTicks = 3   # 0.6s 后自动关闭
        } else {
          $script:runTimer.Stop()
          $progBar.Visible = $false
          $titleLabel.Text = "安装失败"
          $lblT1.Text = "安装失败 "
          $lblT1.ForeColor = [System.Drawing.Color]::FromArgb(220, 38, 38)
          $lblD.Text = "安装脚本退出码 " + $script:runExit + "，请重试或联系发布者。"
          $btnOk.Text = "关  闭"
          $btnOk.Visible = $true
          $script:doneReady = $true
        }
        return
      }
      # 进行中：按已复制字节占比推进，平滑递增（每次最多 +2%）
      if ($script:totalBytes -gt 0) {
        $copied = (Get-FolderBytes $script:dstPath) - $script:initBytes
        $target = [int](99.0 * $copied / $script:totalBytes)
        if ($target -gt $script:shownPct) {
          $script:shownPct = [Math]::Min($script:shownPct + 2, $target)
          $progBar.Value = [Math]::Min(99, $script:shownPct)
        }
      }
    })
    $script:runTimer.Start()
    return
  }
  $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
  $form.Close()
})
$form.Controls.Add($btnOk)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "取消"
$btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCancel.FlatAppearance.BorderSize = 1
$btnCancel.FlatAppearance.BorderColor = $C_LINE
$btnCancel.BackColor = [System.Drawing.Color]::White
$btnCancel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9.75)
$btnCancel.ForeColor = $C_GRAY_D
$btnCancel.Location = New-Object System.Drawing.Point(582, $Y_BTN)
$btnCancel.Size = New-Object System.Drawing.Size(74, $H_BTN)
$btnCancel.Region = New-Object System.Drawing.Region((New-RoundPath 74 $H_BTN 10))
$btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.Controls.Add($btnCancel)

$form.CancelButton = $btnCancel
$form.Add_Shown({ $txt.Select($txt.Text.Length, 0); $txt.Focus() })

$dlgResult = $form.ShowDialog()

if ($dlgResult -eq [System.Windows.Forms.DialogResult]::OK) {
  # 全程不显示控制台（用户定标准：任何阶段都不要黑窗），复制在后台静默完成
  Write-Output $txt.Text.Trim()
  exit 0
}
exit 1
