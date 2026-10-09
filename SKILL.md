---
name: make-sfx
description: 把任意文件夹打成 Windows 单文件自解压 .exe（7-Zip SFX）。适用于「打包成 exe」「自解压」「自解压安装包」「绿色版/免安装版打包」「软件打包成一个文件」「把配置/主题打包发给别人」「指定解压路径」「解压后自动运行程序」「自动创建桌面快捷方式」「SFX」「单文件分发」「portable exe」等需求，也适用于排查「SFX 解压后没自动运行」「config.txt 不生效」「SFX 大小变成 196KB」「7z.sfx 和 7zSD.sfx 该用哪个」这类问题。
---

# make-sfx — Windows 单文件自解压打包

把文件夹打成双击即用的单个 `.exe`，只用 7-Zip，不需要 NSIS / Inno Setup。

## 两种标准用例（先判断属于哪种）

**接到打包需求，先分析文件夹内容再选模式**：
- 有 `.exe` / `.dll` / `app.asar`（Electron）/ 大体积运行时 → **用例① 软件安装**
- 主题（css/主题文件夹）、配置（json/yaml/toml/conf）、代码片段、字体 → **用例② 配置文件包**

### 用例① 软件安装

解压到指定安装目录（如 `D:\software\<App>`）→ 创建桌面快捷方式 → 启动主程序。
骨架见下方「安装器模式」章节；UI 用固定标准 `wizard.ps1`（见「自定义安装界面」）。

**图标规则（默认标准）**：软件包的图标（exe 图标 + 向导左上角）**优先用被封装软件自己的图标**——
`python scripts\extract_icon.py <主程序.exe> app.ico` 一键提取（含全部尺寸），再 `-Icon app.ico` 打包。
取不到图标或打包**配置文件包**（用例②）时，才退回 rar.ico（大强出品标识）。

### 用例② 配置文件包（识别目标路径 + 覆盖安装）

**路径识别**：目标是软件的用户目录，**必须用环境变量表示**（不同用户名不一样，绝不硬编码路径）：

| 内容 | 目标路径（写进 install 脚本） |
|---|---|
| Typora 主题 | `%APPDATA%\Typora\themes` |
| 一般软件配置（Roaming） | `%APPDATA%\<软件名>\...` |
| 一般软件缓存/插件（Local） | `%LOCALAPPDATA%\<软件名>\...` |
| 跨用户公共配置 | `%PROGRAMDATA%\<软件名>\...` |

遇到没见过的软件：先在目标机（或用户确认）找到现有配置目录定位，再写进脚本。

**覆盖操作**：配置包就是要覆盖旧文件，robocopy 必须加 `/IS /IT`
（`/IS` 连相同文件也复制、`/IT` 包含被改过的——不加的话 robocopy 默认跳过"相同"文件）：

```cmd
robocopy "%SRC%" "%DST%" /E /IS /IT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 exit /b 1
```

**与用例①的差异**：不建桌面快捷方式、不启动主程序（可选 `start "" explorer "%DST%"` 打开目标目录让用户确认）。
模板见 `scripts\install_config.cmd`（纯 ASCII，把 `SRC`/`DST` 换成项目实际值即可）。
UI 仍然用固定标准 `wizard.ps1`——`-Default` 传解析后的环境变量路径（cmd 里 `set "DEFAULT=%APPDATA%\Typora\themes"` 再传），
用户在对话框里看到/确认目标位置后开始覆盖安装。

## 先看这张表（选错 stub = 白干）

⚠️ **最重要的事实**：`C:\Program Files\7-Zip\` 里自带的 `7z.sfx` **完全不读 config.txt**。
（已实测：`Directory=`、`RunProgram=` 全部被忽略，文件直接平铺解压到 exe 所在目录。）

| stub | 从哪来 | 读 config.txt | 解压到 | 自动运行程序 | 用户能选目录 | 大小 |
|---|---|---|---|---|---|---|
| `7z.sfx` | Program Files 自带 | ❌ 完全忽略 | **exe 所在目录** | ❌ | ✅ 7-Zip 解压对话框里可改 | 215K |
| `7zCon.sfx` | Program Files 自带 | ❌ | 命令行 `-o` 指定 | ❌ | ❌ | 193K |
| `7zS2.sfx` / `7zS2con.sfx` | LZMA SDK `bin/` | 仅 `Directory` | `%TEMP%`，退出后删除 | ❌ | ❌ | 35K |
| **`7zSD.sfx`** | **LZMA SDK `bin/`** | ✅ | `%TEMP%\7zS*\`，退出后**删除** | ✅ `RunProgram` | ❌ | 128K |
| modSFX `7zSD*.sfx` | 第三方 7zsfx.info | ✅（超集） | 用户可选，**保留** | ✅ | ✅ `InstallPath` | — |

**怎么选：**
- "打包成一个 exe 发给别人，让他自己选解压位置" → `7z.sfx` 就够，零依赖。
- **"解压后自动跑程序 / 装到指定路径 / 建快捷方式" → 必须用 `7zSD.sfx`**（官方 LZMA SDK 里的那个）。
- 需要"让用户选安装目录" → 才需要第三方 modSFX。

## 拿到 7zSD.sfx（官方渠道）

它**不在** Program Files，也**不在** `7z_extra` 包里。在 **LZMA SDK** 里：

```powershell
# 下载 https://www.7-zip.org/a/lzma2602.7z ，解出 bin/7zSD.sfx
& "C:\Program Files\7-Zip\7z.exe" x -y -o<sdk> lzma2602.7z "bin/*"
```

## 用法

```powershell
# ① 简单打包 + 换图标（7z.sfx，零依赖）
powershell -ExecutionPolicy Bypass -File scripts\build_sfx.ps1 `
  -Source "D:\MyApp" -Output "D:\dist\MyApp-portable.exe" -Icon "D:\MyApp\app.ico"

# ② 安装器式：装到固定路径 + 自动运行 + 建桌面快捷方式（7zSD.sfx）
powershell -ExecutionPolicy Bypass -File scripts\build_sfx.ps1 `
  -Stub "D:\tools\7zSD.sfx" -Output "$env:USERPROFILE\Desktop\MyApp-Setup.exe" `
  -AddItems "D:\build\install.cmd","D:\build\MyApp-win32-x64" `
  -Title "MyApp 安装程序" -BeginPrompt "即将安装到 D:\software\MyApp，是否继续？" `
  -RunProgram "install.cmd"
```

参数：`-Source` 单个文件夹（内容铺到归档根）、`-AddItems` 额外顶层项（保持原名，用来把 **安装脚本 + 程序目录** 一起塞进归档根）、
`-Output` 输出 exe、`-Stub` stub 路径（默认 `7z.sfx`）、`-Icon` 换图标、`-Exclude` 排除、
`-Title`/`-BeginPrompt`/`-Progress`/`-Directory`/`-RunProgram`（**仅 7zSD 生效**）、
`-ResLang` 图标资源语言 ID（默认 `0x409`，必须与目标 stub 已有的一致）、`-KeepWork` 保留中间文件。

## 默认值（sfx-defaults.txt）

脚本同目录下的 `sfx-defaults.txt`（UTF-8 **带 BOM**）可以固化常用配置，命令行没传时自动取用：

```
# 井号开头是注释
Icon=D:\software\自解压文件制作\rar.ico
Stub=C:\Users\Administrator\.agents\tools\7zip-extra\sdk\bin\7zSD-zh.sfx
```

- 只识别 `Icon=` 和 `Stub=` 两个键（`-Icon` / `-Stub` 显式传参优先级更高）。
- 读取发生在 stub 存在性校验**之前**，所以默认 stub 路径写错会直接报「找不到 …」。
- 本机把 `7zSD-zh.sfx`（已中文化）和 `rar.ico` 设为默认，等于"开箱就是中文安装器 + 图标"。

## 安装器模式（用例②）的标准骨架

`7zSD.sfx` 的运行模型：**解压到 `%TEMP%\7zSxxxx\` → 以该目录为 CWD 执行 `RunProgram` → 等它退出 → 删掉临时目录**。
所以 `RunProgram` 指向的脚本必须**先把文件搬到永久位置，再启动程序**，绝不能直接在 temp 里跑主程序。

`install.cmd`（放归档根，`RunProgram="install.cmd"`）：

```cmd
@echo off
set "SRC=%~dp0MyApp-win32-x64"
set "DST=D:\software\MyApp"
if not exist "%DST%" mkdir "%DST%"
robocopy "%SRC%" "%DST%" /E /R:2 /W:1 /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 exit /b 1
powershell -NoProfile -Command "$w=New-Object -ComObject WScript.Shell; $l=$w.CreateShortcut([Environment]::GetFolderPath('Desktop')+'\MyApp.lnk'); $l.TargetPath='%DST%\MyApp.exe'; $l.WorkingDirectory='%DST%'; $l.IconLocation='%DST%\MyApp.exe,0'; $l.Save()"
start "" /D "%DST%" "%DST%\MyApp.exe"
exit /b 0
```

要点：
- `install.cmd` **保持纯 ASCII**，避开 cmd 代码页问题；用户可见的中文放 `Title`/`BeginPrompt`（config.txt 是 UTF-8，安全）和 `choose_path.ps1`（带 BOM 的 .ps1）。
- `robocopy` 退出码 0–7 = 成功，`if errorlevel 8` 才算失败。
- `start "" /D "%DST%"` 让主程序的工作目录是安装目录，不是即将被删的 temp。
- `%ERRORLEVEL%` 在 `if (...)` 块里会被提前展开成 0，别在块内打印它。

## 自定义安装界面（wizard.ps1，固定标准 UI）

**用户已定标准：以后所有软件的安装包统一用这套 UI**，每个项目只改三样：`-AppName`（应用名）、
横幅图片（可选）、默认安装路径。左上角图标固定用 rar.ico（WinRAR 图标）；
**软件包图标用被封装软件自己的图标**（`extract_icon.py` 提取）。

**默认横幅（固定标准）**：`assets\banner-dqtx.png` = DQTX 标准横幅（头像 + 公众号：大强同学 + 官网 dqtx.cc，
2172x472 已裁白边）。项目没有自己的横幅时**不用传 `-Banner`**，wizard.ps1 自动回退：
先找脚本同目录 `banner-dqtx.png`，再找 `..\assets\banner-dqtx.png`。
打包时建议把 `assets\banner-dqtx.png` 拷进暂存目录与 wizard.ps1 同放。

`scripts\wizard.ps1` = 现代扁平风格向导（无边框自绘标题栏 + 横幅 + 路径选择二合一）：

- **标题栏**：自绘（无系统边框），左上角 rar.ico（`-Icon`，默认取脚本同目录 `rar.ico`）+
  标题 +「— / ✕」按钮，整个标题栏和横幅可拖动；圆角窗口（Region 12px）。
- **横幅**：`-Banner` 传入图片（jpg/png 按内容识别），`StretchImage` 铺满；**PNG 若自带白边
  会造成"横幅和标题栏之间有缝"——先用 `scripts\crop_banner.ps1` 自动裁掉四周留白再打包**。
  不传则自动使用 DQTX 标准横幅（见上）。窗口宽 680、横幅高 148，即按 2172x472 等比；
  换其他比例的横幅时同步改脚本顶部 `H_BANNER`（= 680 * 原高 / 原宽）。
- **内容区**："即将安装 `<AppName>`"（应用名蓝色高亮）→ 灰色说明行 → "安装到以下位置：" →
  浅蓝描边输入框（默认路径 `-Default`）+ 圆角「浏览...」→ 左下绿勾 + `-Tagline`（默认"安全 · 绿色 · 纯净"）
  → 右下蓝色圆角「开始安装 →」+ 白底描边「取消」。
- 传 `-AppName` 后：浏览选中的文件夹会自动加 `\应用名` 子文件夹（防误选盘根平铺）。
- **只往 stdout 打印最终路径一行**，提示全走 GUI；「取消 / ✕」→ `exit 1` → cmd 侧 `DST` 未定义。
- `install.cmd` 里的调用（`powershell` 必须带 `-STA`）：

```cmd
set "DST="
for /f "usebackq delims=" %%i in (`powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0wizard.ps1" -Default "%DEFAULT%" -AppName "MyApp" -Banner "%~dp0banner.png"`) do set "DST=%%i"
if not defined DST (
  echo   [INFO] Cancelled by user.
  exit /b 0
)
```

- **中文参数别写在 cmd 里**（cmd 要保持纯 ASCII）——把 `-Title` 等中文默认值
  直接改在项目自己的 wizard.ps1 副本里（.ps1 是 UTF-8 BOM，中文安全）。
- 打包清单：`install.cmd` + `wizard.ps1` + `rar.ico` + `banner*.png` + 程序目录，全部进 `-AddItems`。
- ⚠️ 流程顺序无法改变：7zSD 是**先解压到 `%TEMP%`、后跑 RunProgram**。去掉 BeginPrompt 后
  双击的体验是：先弹"数据解压中"进度条（几十秒）→ 再弹这个自定义对话框 → 复制到目标 → 启动。
  想要"先出界面/先选路径再解压"只能换第三方 modSFX（7zsfx.info 的魔改 7zSD，未签名二进制，需自行信任）。
- 极简变体：`scripts\choose_path.ps1`（无横幅无标题栏的纯路径选择框）。

## 界面中文化（localize_stub.py）

`7zSD.sfx` 的界面文字存在 PE 资源节的 RT_STRING 表里（每表 16 条 `[u16长度][UTF-16字符]`），直接改字节即可：

| StrID | 原文 | 已改成 |
|---|---|---|
| 3300 | Extracting | 数据解压中 |
| 7 | Extraction Failed | 解压失败 |
| 8 | File is corrupt | 文件已损坏 |
| 3003 | Cannot create folder '{0}' | 无法创建文件夹 '{0}' |

⚠️ 只翻 RT_STRING **不够**——进度框的 `Cancel` 按钮烧在 RT_DIALOG 对话框模板里，
`Are you sure you want to cancel?` / `Unknown error` 是 .rdata 硬编码字面量，都不走字符串表。
`localize_stub.py` 已内置「等长 UTF-16 字节补丁」处理这三处（新串字符数必须与原文一致，空格居中补齐）：

| 位置 | 原文 | 已改成 |
|---|---|---|
| RT_DIALOG 按钮 | Cancel | `  取消  ` |
| .rdata 确认框 | Are you sure you want to cancel? | 确定要取消当前解压吗？（空格居中） |
| .rdata 错误提示 | Unknown error | 未知错误（空格居中） |

进度框标题是动态的「N% 数据解压中」，无需处理。

```powershell
python scripts\localize_stub.py <stub.sfx>            # 就地改
python scripts\localize_stub.py <stub.sfx> -o <out.sfx>
```

已改好的存放在 `C:\Users\Administrator\.agents\tools\7zip-extra\sdk\bin\7zSD-zh.sfx`。
原理：新内容比原块短时用 `\0` 补齐到原大小，解析器按 16 条读完即止，多余的字节不会被读。

## 六个必须记住的雷（都踩过）

1. **`Directory` 不是"解压路径"，是 `RunProgram` 的前缀。**
   源码 `dirPrefix + appLaunched` 直接字符串相加：写 `Directory="."` 会得到 `.install.cmd`（找不到文件，静默失败）。
   **默认 `.\` 就是对的——不需要就别传这个参数。** 想指定安装位置请写进 `install.cmd`。
2. **图标必须 stamp 在 stub 副本上，再 concat。** `UpdateResource()` 把 PE image size 当 EOF，
   对已拼接的 exe 盖章会把 appended payload 截掉（12MB → 196KB）。
3. **config.txt 必须 UTF-8 BOM + CRLF**（开头固定 `;!@Install@!UTF-8!`）。缺 BOM 或用 LF → 整个 config 被当二进制跳过。
   同理 **`.ps1` 必须带 BOM**（PS 5.1 否则用 ANSI 代码页读中文字面值）。
   反过来 **SKILL.md 绝对不能带 BOM**（frontmatter 解析器要求 `---` 在 byte 0）。
4. **`7z.sfx` 忽略 config。** 见上表。别对着它调 `Directory`/`RunProgram` 调半天——脚本会主动告警。
5. **PowerShell 没有 `[ushort]` 这个类型加速器。** 写 `param([ushort]$Lang = 0x409)` 会在
   **参数绑定阶段**直接抛 `找不到类型 [ushort]`——脚本一行都没执行，没有日志、没有半成品，
   看起来像"构建静默失败了"。正确写法是 `[uint16]` / `[UInt16]`。
   （C# `Add-Type` 里的 `ushort` 是合法的，别一起改。）
6. **盖章图标的语言 ID 必须匹配 stub 已有的语言**，否则 `UpdateResource` 是**新增**而不是**替换**，
   结果 PE 里躺着两份 `RT_GROUP_ICON`（`0x0` 和 `0x409`），资源管理器取到哪份看运气 → 图标时灵时不灵。
   先探测目标 stub 的语言（本机 `7zSD.sfx` 是 `0x409`），再用 `-ResLang` 对齐。

## 验证产物

```powershell
.\MyApp-Setup.exe -y        # -y 跳过所有对话框，静默跑完 RunProgram
```
`-y` 用于脚本化自测；正式交付时不加，双击即走正常对话框流程。

## 依赖

- 打包机：`7z.exe`（`C:\Program Files\7-Zip\`）。
- 目标机：**什么都不用装**（解码器已编译进 stub）。
