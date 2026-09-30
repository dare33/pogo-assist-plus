@echo off
setlocal
rem Double-click, or drag a folder of screen-recording clips onto this file.
rem Merges the clips of one Pokemon GO box into one Poke Genie-layout CSV (see docs/whole-box.md).
rem Paths are always quoted and set with set "VAR=..." so "&" and spaces in a Drive folder name
rem (for example "F. Hobbies & Gaming") do not break the script.

set "FOLDER=%~1"
if not defined FOLDER goto :ask
goto :have

:ask
set /p "FOLDER=Folder of recordings (paste the path; next time you can drag the folder onto this file): "
if not defined FOLDER goto :end

:have
rem A pasted path may carry quotes or a trailing backslash; either would break the argument.
set "FOLDER=%FOLDER:"=%"
if "%FOLDER:~-1%"=="\" set "FOLDER=%FOLDER:~0,-1%"

where node >nul 2>nul
if errorlevel 1 goto :nonode

rem The tier-list repo's inbox is where the CSV is consumed; copy it there when that folder exists.
set "INBOXARG="
if exist "%USERPROFILE%\dare33\pokemon-go-tier-list\inbox\" set INBOXARG=--inbox "%USERPROFILE%\dare33\pokemon-go-tier-list\inbox"

node "%~dp0scripts\extract-box.mjs" "%FOLDER%" %2 %3 %4 %5 %6 %7 %8 %9 %INBOXARG%
goto :end

:nonode
echo Node.js is not installed: https://nodejs.org

:end
echo.
pause
endlocal
