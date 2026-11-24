@echo off
rem ASCII only on purpose (cmd code pages garble Korean text inside .bat files).
rem Double-click to run the interactive Korean setup guide. Nothing is changed without your confirmation.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "skills\wmux-global-agents\scripts\guide.ps1"
echo.
pause
