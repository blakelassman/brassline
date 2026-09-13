@echo off
setlocal
cd /d "%~dp0"
"engine\Godot_v4.7.2-stable_win64_console.exe" --path "%~dp0." --log-file "%~dp0brassline.log"
echo.
echo Send the error text above or the brassline.log file for help.
pause
