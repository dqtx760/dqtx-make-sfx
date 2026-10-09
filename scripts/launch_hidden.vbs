' launch_hidden.vbs — hidden launcher for 7zSD RunProgram (keep this file pure ASCII)
'
' Why: 7zSD (GUI app, no console) running RunProgram="install.cmd" creates a NEW
' visible console window -> the ugly cmd flash. wscript.exe is GUI-subsystem too,
' and WshShell.Run(..., 0, True) creates the child console fully hidden, so the
' batch runs with zero console flash. Exit code is propagated back to 7zSD.
'
' Usage (config.txt):
'   RunProgram="launch_hidden.vbs"
' (7zSD RunProgram accepts ONE file only - no arguments - so the script name is
'  hardcoded as install.cmd; override by passing the target as an argument.
'  Do NOT set Directory in config.txt: 7zSD prepends it to RunProgram.
'  CWD is already the temp extract dir.)

Option Explicit
Dim shell, fso, dir, target, rc
Set shell = CreateObject("WScript.Shell")
Set fso   = CreateObject("Scripting.FileSystemObject")

dir = fso.GetParentFolderName(WScript.ScriptFullName)
If WScript.Arguments.Count >= 1 Then
  target = fso.BuildPath(dir, WScript.Arguments(0))
Else
  target = fso.BuildPath(dir, "install.cmd")
End If
shell.CurrentDirectory = dir

rc = shell.Run("cmd.exe /c """ & target & """", 0, True)
WScript.Quit rc
