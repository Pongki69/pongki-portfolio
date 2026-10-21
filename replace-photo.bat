@echo off
setlocal
cd /d "%~dp0"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0replace-photo.ps1"
set "RESULT=%ERRORLEVEL%"

echo.
if not "%RESULT%"=="0" (
  echo Photo update did not finish. Read the message above, fix the issue, and run this file again.
) else (
  echo Photo update finished.
)
pause
exit /b %RESULT%
