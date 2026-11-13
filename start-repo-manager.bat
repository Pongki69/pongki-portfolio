@echo off
setlocal
title Pongki Portfolio Project Manager
echo.
echo  PONGKI PORTFOLIO PROJECT MANAGER
echo.
echo  [1] Run the service
echo  [2] Stop the service
echo  [3] Exit
echo.
choice /C 123 /N /M "Choose an option: "
if errorlevel 3 exit /b 0
if errorlevel 2 goto stop
if errorlevel 1 goto run

:run
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-repo-manager.ps1" -Mode start
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:stop
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-repo-manager.ps1" -Mode stop
pause
exit /b %ERRORLEVEL%
