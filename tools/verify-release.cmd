@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify-release.ps1" %*
exit /b %ERRORLEVEL%
