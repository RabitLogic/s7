@echo off
cd /d C:\Users\Rabit\moonbit\s7
echo Starting build... > build_log.txt
C:\Users\Rabit\.moon\bin\moon.exe build --target native >> build_log.txt 2>&1
echo EXIT CODE: %ERRORLEVEL% >> build_log.txt
dir /s /b _build\*.exe >> build_log.txt 2>&1
echo DONE >> build_log.txt
