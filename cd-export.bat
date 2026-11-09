@echo off
REM Copy a patient's exams to a CD (or a folder, or a disc image). Double-click.
REM   cd-export.bat            French     cd-export.bat -Lang ko   Korean     -Lang en   English
REM Sign in with an EMR account. Nothing is installed; no system setting is changed.
start "" powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0cd-export.ps1" %*
