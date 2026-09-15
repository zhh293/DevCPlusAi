@echo off
cd /d "%~dp0"

set MINGW=C:\Users\rain_\mingw\x86_64-8.1.0-release-posix-seh-rt_v6-rev0\mingw64\bin

if not exist "%MINGW%\g++.exe" (
    echo [ERROR] g++.exe not found at:
    echo         %MINGW%
    echo.
    echo Please edit this .bat and fix the MINGW path.
    pause
    exit /b 1
)

echo ========================================
echo  [1/3] Compiling test1.cpp ...
echo ========================================
"%MINGW%\g++.exe" test1.cpp -o test1.exe -std=c++11

if errorlevel 1 (
    echo.
    echo *** COMPILE FAILED - see errors above ***
    pause
    exit /b 1
)

echo.
echo ========================================
echo  [2/3] Compile OK. Running:
echo ========================================
test1.exe
echo ========================================
echo  [3/3] Program exited.
echo ========================================
pause
