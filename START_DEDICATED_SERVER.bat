@echo off
setlocal
cd /d "%~dp0"
echo BRASSLINE 0.7.1 dedicated server - UDP port configured in server.cfg
echo Friends join your public IP. On this PC, join 127.0.0.1.
echo Close this window to stop the server.
"%~dp0engine\Godot_v4.7.2-stable_win64_console.exe" --headless --path "%~dp0." --log-file "%~dp0server.log" -- --server
if errorlevel 1 (
  echo Server stopped with an error. See server.log.
  pause
)
