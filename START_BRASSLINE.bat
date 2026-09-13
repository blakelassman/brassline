@echo off
setlocal
cd /d "%~dp0"
if not exist "engine\Godot_v4.7.2-stable_win64.exe" (
  echo The game engine is missing. Extract the entire ZIP first.
  pause
  exit /b 1
)
start "Brassline" "engine\Godot_v4.7.2-stable_win64.exe" --path "%~dp0." --log-file "%~dp0brassline.log"
