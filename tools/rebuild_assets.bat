@echo off
REM Rebuilds characters and animations from the asset folders.
REM
REM Usage: drop a character export into assets\characters\<name>\, or animation
REM files into assets\animations\source\ (or a character's own animations\
REM subfolder), then run this.
REM
REM Doing the same thing inside the editor: Project > Tools > Rebuild Characters
REM & Animations (or just drop the files in - the Asset Pipeline addon picks
REM them up on its own).

setlocal
set "PROJECT=%~dp0.."
set "GODOT=D:\download\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe"

if not exist "%GODOT%" (
    echo [!] Godot not found at:
    echo     %GODOT%
    echo     Edit the GODOT variable at the top of this file.
    exit /b 1
)

echo.
echo === 1/6  importing new files ===============================
"%GODOT%" --headless --path "%PROJECT%" --import || goto :failed

echo.
echo === 2/6  detecting animation rigs, assigning bone maps =====
"%GODOT%" --headless --path "%PROJECT%" --script res://tools/setup_anim_imports.gd || goto :failed

echo.
echo === 3/6  detecting character rigs, scale and pose ==========
"%GODOT%" --headless --path "%PROJECT%" --script res://tools/setup_character_imports.gd || goto :failed

echo.
echo === 4/6  reimporting with retargeting ======================
"%GODOT%" --headless --path "%PROJECT%" --import || goto :failed

echo.
echo === 5/6  building animation libraries ======================
"%GODOT%" --headless --path "%PROJECT%" --script res://tools/build_anim_library.gd || goto :failed

echo.
echo === 6/6  building character scenes =========================
"%GODOT%" --headless --path "%PROJECT%" --script res://tools/build_character_scenes.gd || goto :failed

echo.
echo Done. Press F5 in the editor for the main menu (animation debug / playground).
exit /b 0

:failed
echo.
echo [!] step failed - see the output above.
exit /b 1
