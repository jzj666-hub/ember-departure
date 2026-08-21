@echo off
setlocal enabledelayedexpansion

set "PROJECT=%~dp0.."
set "GODOT=D:\download\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe"
set "CHAR_ID=%~1"

if exist "%PROJECT%\assets\characters\%~nx1" (
    set "CHAR_ID=%~nx1"
)

if not "%CHAR_ID%"=="" goto :validate

echo ========================================================
echo   Character Rebuilder
echo ========================================================
echo.
echo Available characters in assets\characters:
echo --------------------------------------------------------
set /a count=0
for /d %%D in ("%PROJECT%\assets\characters\*") do (
    set /a count+=1
    set "CHAR_!count!=%%~nxD"
    echo   [!count!] %%~nxD
)
echo --------------------------------------------------------

if %count%==0 (
    echo [!] No characters found in assets\characters\
    pause
    exit /b 1
)

set "CHOICE="
set /p "CHOICE=Select a character number (1-%count%) or enter character ID: "

if "%CHOICE%"=="" (
    echo [!] No selection made.
    pause
    exit /b 1
)

if defined CHAR_%CHOICE% (
    for %%V in ("CHAR_%CHOICE%") do set "CHAR_ID=!%%~V!"
) else (
    set "CHAR_ID=%CHOICE%"
)

:validate
if not exist "%PROJECT%\assets\characters\%CHAR_ID%" (
    echo.
    echo [!] Character directory not found: assets\characters\%CHAR_ID%
    echo.
    pause
    exit /b 1
)

if not exist "%GODOT%" (
    echo.
    echo [!] Godot not found at:
    echo     %GODOT%
    echo     Edit the GODOT variable at the top of this file.
    echo.
    pause
    exit /b 1
)

echo.
echo ========================================================
echo Rebuilding character: %CHAR_ID%
echo ========================================================

echo.
echo === 1/4  detecting rig, scale and pose for %CHAR_ID% =====
"%GODOT%" --headless --path "%PROJECT%" --script res://tools/setup_single_character.gd -- "%CHAR_ID%"
if %ERRORLEVEL% NEQ 0 goto :failed

echo.
echo === 2/4  importing / reimporting model =====================
"%GODOT%" --headless --path "%PROJECT%" --import
if %ERRORLEVEL% NEQ 0 goto :failed

echo.
echo === 3/4  building wrapper scene and local animations =======
"%GODOT%" --headless --path "%PROJECT%" --script res://tools/build_single_character.gd -- "%CHAR_ID%"
if %ERRORLEVEL% NEQ 0 goto :failed

echo.
echo ========================================================
echo Done! Character '%CHAR_ID%' rebuilt successfully.
echo ========================================================
echo.
pause
exit /b 0

:failed
echo.
echo ========================================================
echo [!] Rebuild failed for character: %CHAR_ID%
echo ========================================================
echo.
pause
exit /b 1
