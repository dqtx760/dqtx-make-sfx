@echo off
setlocal EnableExtensions
title Config Installer

rem ============================================================
rem  CONFIG-MODE installer (template)
rem  Use case: theme / config / snippet packs -> user profile dir.
rem  Rules:
rem   - DST MUST use environment variables (%APPDATA%, %LOCALAPPDATA%,
rem     %USERPROFILE% ...). NEVER hardcode usernames.
rem   - Overwrite is mandatory: robocopy /IS /IT forces copying even
rem     if target files are identical/tweaked.
rem   - Config mode: no desktop shortcut, no app launch (add
rem     "start "" "%DST%"" at the end only if you want to reveal
rem     the folder in Explorer).
rem ============================================================

set "SRC=%~dp0ConfigFiles"
set "DST=%APPDATA%\Typora\themes"

echo.
echo   ==========================================
echo    Config Installer
echo   ==========================================
echo    Source : %SRC%
echo    Target : %DST%
echo.

if not exist "%SRC%" (
  echo   [ERROR] Payload missing: %SRC%
  echo.
  pause
  exit /b 1
)

if not exist "%DST%" mkdir "%DST%" >nul 2>&1

echo   [1/2] Copying and overwriting files...
robocopy "%SRC%" "%DST%" /E /IS /IT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 (
  echo   [ERROR] Copy failed. Check disk space / permissions.
  echo.
  pause
  exit /b 1
)

echo   [2/2] Done.
rem --- optional: reveal the target folder ---
rem start "" explorer "%DST%"
exit /b 0
