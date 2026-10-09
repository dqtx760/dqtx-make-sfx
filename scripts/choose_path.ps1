param(
  [string]$Default = "",        # 输入框默认路径（建议 "D:\software\MyApp" 这种带应用名的完整路径）
  [string]$AppName = "",        # 应用名。提供后，「浏览」选中的文件夹下会自动加 \AppName 子文件夹
  [string]$Title   = "选择安装位置"
)

# 作用：给 7zSD.sfx 安装器补一个「用户可选解压路径」的对话框（官方 7zSD 没有这个能力）。
# 用法：install.cmd 里用 for /f 捕获 stdout：
#   for /f "usebackq delims=" %%i in (`powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0choose_path.ps1" -Default "%DEFAULT%" -AppName "MyApp"`) do set "DST=%%i"
# 用户点「取消」或校验不过 → exit 1，DST 保持未定义。
# 注意：本文件必须存成 UTF-8 **带 BOM**（PS 5.1 否则按 ANSI 读，中文会乱码）。
# 输出约定：只往 stdout 打印最终路径一行，其他任何提示都用 MessageBox，别用 Write-Host。

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form                     = New-Object System.Windows.Forms.Form
$form.Text                = $Title
$form.ClientSize          = New-Object System.Drawing.Size(576, 130)
$form.FormBorderStyle     = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.StartPosition       = "CenterScreen"
$form.MaximizeBox         = $false
$form.MinimizeBox         = $false
$form.TopMost             = $true
$form.ShowInTaskbar       = $false

$lbl = New-Object System.Windows.Forms.Label
if ($AppName) { $lbl.Text = "解压到文件夹（将在所选位置创建 $AppName 子文件夹）：" }
else          { $lbl.Text = "解压到文件夹：" }
$lbl.AutoSize = $true
$lbl.Location = New-Object System.Drawing.Point(14, 14)
$form.Controls.Add($lbl)

$txt = New-Object System.Windows.Forms.TextBox
$txt.Location = New-Object System.Drawing.Point(16, 40)
$txt.Size     = New-Object System.Drawing.Size(480, 24)
$txt.Text     = $Default
$form.Controls.Add($txt)

$btnBrowse          = New-Object System.Windows.Forms.Button
$btnBrowse.Text     = "浏览..."
$btnBrowse.Size     = New-Object System.Drawing.Size(70, 24)
$btnBrowse.Location = New-Object System.Drawing.Point(504, 39)
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

$btnOk          = New-Object System.Windows.Forms.Button
$btnOk.Text     = "开始安装"
$btnOk.Size     = New-Object System.Drawing.Size(88, 26)
$btnOk.Location = New-Object System.Drawing.Point(396, 88)
$btnOk.Add_Click({
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
  $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
  $form.Close()
})
$form.Controls.Add($btnOk)

$btnCancel              = New-Object System.Windows.Forms.Button
$btnCancel.Text         = "取消"
$btnCancel.Size         = New-Object System.Drawing.Size(70, 26)
$btnCancel.Location     = New-Object System.Drawing.Point(492, 88)
$btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.Controls.Add($btnCancel)

$form.AcceptButton = $btnOk
$form.CancelButton = $btnCancel
$form.Add_Shown({ $txt.Select($txt.Text.Length, 0); $txt.Focus() })

if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output $txt.Text.Trim()
  exit 0
}
exit 1
