@echo off
setlocal
cd /d "%~dp0.."
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars32.bat" >nul
if errorlevel 1 exit /b 1
if not exist .tools\web-probe mkdir .tools\web-probe
cl /nologo /LD /MT /EHsc /std:c++17 /I.tools\webview-sdk\extracted\build\native\include Source\AgentWeb\Native\AgentWebHost.cpp /Fo.tools\web-probe\AgentWebHost.obj /link /DEF:Source\AgentWeb\Native\AgentWebHost.def /OUT:.tools\web-probe\AgentWebHost.dll /IMPLIB:.tools\web-probe\AgentWebHost.lib .tools\webview-sdk\extracted\build\native\x86\WebView2LoaderStatic.lib user32.lib ole32.lib version.lib shlwapi.lib advapi32.lib
if errorlevel 1 exit /b 1
"C:\Program Files (x86)\Borland\Delphi7\Bin\dcc32.exe" -B -N.tools\web-probe -E.tools\web-probe Source\Tests\AgentWebProbe.dpr
exit /b %errorlevel%
