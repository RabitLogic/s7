@echo off
cd /d C:\Users\Rabit\moonbit\s7
C:\Users\Rabit\.moon\bin\moon.exe build --target native
echo BUILD EXIT CODE: %ERRORLEVEL%
if exist _build\native\debug\build\main\main.exe (
    echo BINARY FOUND
) else (
    echo BINARY NOT FOUND
    dir /s _build\native 2>nul || echo NO NATIVE BUILD DIR
)
