@echo off
setlocal enabledelayedexpansion

:: Navigate to script directory
cd /d "%~dp0"

:: 0. Check and setup Git environment
where git >nul 2>nul
if errorlevel 1 (
    if exist "D:\xunlei\Git\cmd\git.exe" (
        set "PATH=D:\xunlei\Git\cmd;D:\xunlei\Git\bin;!PATH!"
    ) else if exist "C:\Program Files\Git\cmd\git.exe" (
        set "PATH=C:\Program Files\Git\cmd;C:\Program Files\Git\bin;!PATH!"
    ) else if exist "D:\Git\cmd\git.exe" (
        set "PATH=D:\Git\cmd;D:\Git\bin;!PATH!"
    ) else if exist "C:\Program Files (x86)\Git\cmd\git.exe" (
        set "PATH=C:\Program Files (x86)\Git\cmd;C:\Program Files (x86)\Git\bin;!PATH!"
    )
)

where git >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Git was not found in PATH or standard installation directories.
    echo Please ensure Git is installed.
    goto FAILED
)

echo ===================================================
echo             Automated Git Sync and Push
echo ===================================================
echo.

:: 1. Show Git status
echo [1/4] Checking Git status...
git status -s
echo.

:: 2. Prompt for commit message
set "COMMIT_MSG="
set /p "COMMIT_MSG=Enter commit message (Press Enter for auto timestamp): "

if "!COMMIT_MSG!"=="" (
    for /f "tokens=1-4 delims=/.- " %%a in ("%date%") do (
        set "DATE_STR=%%a-%%b-%%c"
    )
    set "TIME_STR=%time: =0%"
    set "TIME_STR=!TIME_STR:~0,8!"
    set "COMMIT_MSG=Auto commit: !DATE_STR! !TIME_STR!"
)

echo.
echo Commit Message: "!COMMIT_MSG!"
echo.

:: 3. Stage all changes
echo [2/4] Staging changes (git add .)...
git add .
if errorlevel 1 (
    echo [ERROR] git add failed.
    goto FAILED
)

:: 4. Commit
echo [3/4] Committing changes...
git commit -m "!COMMIT_MSG!"
if errorlevel 1 (
    echo [INFO] No changes to commit or working tree clean.
)

:: 5. Push to remote
echo.
echo [4/4] Pushing to remote...

for /f "tokens=*" %%i in ('git rev-parse --abbrev-ref HEAD 2^>nul') do set "BRANCH=%%i"

if "!BRANCH!"=="" (
    echo [INFO] Branch not detected, running default git push...
    git push
) else (
    echo [INFO] Current branch: !BRANCH!
    git push origin !BRANCH!
)

if errorlevel 1 (
    echo.
    echo [ERROR] git push failed. Please check network, proxy, or permissions.
    goto FAILED
)

echo.
echo ===================================================
echo               Git Sync Completed Successfully!
echo ===================================================
goto END

:FAILED
echo.
echo ===================================================
echo               Git Sync Failed!
echo ===================================================

:END
echo.
pause
