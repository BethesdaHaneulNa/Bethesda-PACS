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
echo    Bethesda PACS is running:  http://localhost:9090
echo.
echo    Pairing with the EMR: read the lines ABOVE.
echo     - "paired with the EMR"  : nothing to do.
echo     - otherwise: start the EMR on this PC and run pair-with-emr.ps1,
echo       or paste the Bridge Token shown above into the EMR
echo       (Settings -^> Order Feed -^> Bridge Token).
echo    In the EMR set the PACS viewer URL to the address shown above
echo    (this PC's network address, e.g. http://192.168.x.x:9090 -
echo    not localhost, which only works on this PC).
echo ==================================================
echo.
pause
