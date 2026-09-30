@echo off
setlocal
rem Double-click, or drag a folder of screen-recording clips onto this file.
rem Merges the clips of one Pokemon GO box into one Poke Genie-layout CSV (see docs/whole-box.md).
rem Paths are always quoted and set with set "VAR=..." so "&" and spaces in a Drive folder name
rem (for example "F. Hobbies & Gaming") do not break the script.

where node >nul 2>nul
if errorlevel 1 goto :nonode

rem The tier-list repo's inbox is where the CSV is consumed; copy it there when that folder exists.
rem It goes first so an --inbox given on the command line overrides it.
set "INBOXARG="
if exist "%USERPROFILE%\dare33\pokemon-go-tier-list\inbox\" set INBOXARG=--inbox "%USERPROFILE%\dare33\pokemon-go-tier-list\inbox"

if not "%~1"=="" goto :given

set "FOLDER="
set /p "FOLDER=Folder of recordings (paste the path; next time you can drag the folder onto this file): "
if not defined FOLDER goto :end
rem A pasted path may carry quotes or a trailing backslash (but keep a drive root such as C:\).
set "FOLDER=%FOLDER:"=%"
if "%FOLDER:~-1%"=="\" if not "%FOLDER:~1%"==":\" set "FOLDER=%FOLDER:~0,-1%"
rem A quoted drive root ("C:\") would end in \" and swallow the quote; "C:\." is the same folder and quotes safely.
if "%FOLDER:~-2%"==":\" set "FOLDER=%FOLDER%."
node "%~dp0scripts\extract-box.mjs" %INBOXARG% "%FOLDER%"
goto :end

:given
rem Explorer already quotes paths with spaces; %* keeps that quoting and passes every argument on.
node "%~dp0scripts\extract-box.mjs" %INBOXARG% %*
goto :end

:nonode
echo Node.js is not installed: https://nodejs.org

:end
echo.
pause
endlocal
