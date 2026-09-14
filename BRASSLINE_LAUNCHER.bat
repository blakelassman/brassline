@echo off
setlocal
cd /d "%~dp0"
start "BRASSLINE" powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0launcher\Bootstrap.ps1" -Seed "%~dp0."
