@echo off
REM Watch the imaging devices talk to this PACS, in plain words.
REM Double-click on the server PC while a device is being set up. Stop with Ctrl+C.
REM   device-watch.bat            Korean     device-watch.bat -Lang fr   French
REM Detail mode makes the image server log more for now; Ctrl+C puts it back.
REM If this window was closed with its X instead: run  device-watch.bat -Reset
title Bethesda PACS - device watch
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0device-watch.ps1" -Detail %*
pause
