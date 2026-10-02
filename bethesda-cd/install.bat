@echo off
rem Bethesda CD - put the program on this PC and a shortcut on the desktop (see install.ps1).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
pause
