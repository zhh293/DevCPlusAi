@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0package-portable.ps1" -SelfExtracting %*
exit /b %ERRORLEVEL%
