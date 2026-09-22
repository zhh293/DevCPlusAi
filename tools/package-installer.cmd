@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0package-installer.ps1" %*
exit /b %errorlevel%
