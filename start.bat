@echo off
title Bethesda PACS
color 0B
echo ==================================================
echo    Bethesda PACS  (medical imaging)
echo ==================================================
echo.

REM --- 1) Is Docker running? ---
docker info >nul 2>&1
if errorlevel 1 (
  color 0E
  echo  [!] Docker Desktop is not running yet.
  echo      Open "Docker Desktop", wait until it says "Engine running",
  echo      then double-click this start file again.
  echo.
  pause
  exit /b 1
)

echo  Starting Bethesda PACS...
echo  The first time, this downloads Orthanc and builds the bridge and can
echo  take a few minutes. Please wait - do not close this window.
echo.

REM --- 2) Generate secrets (first run) and start ---
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
if errorlevel 1 (
  color 0C
  echo.
  echo  [!] Something went wrong while starting. Please share this window's text for help.
  echo.
  pause
  exit /b 1
)

color 0A
echo.
echo ==================================================
echo    Bethesda PACS is running:  http://localhost:8090
echo.
echo    IMPORTANT - pair it with the EMR (one time):
echo    copy the Bridge Token shown ABOVE, then in the EMR open
echo    Settings -^> Order Feed -^> Bridge Token and paste it there.
echo    Also set the PACS viewer URL to  http://localhost:8090
echo ==================================================
echo.
pause
