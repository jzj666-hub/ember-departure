@echo off
REM Start GitHub Copilot CLI from project root
pushd "%~dp0\.."
where copilot >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
  echo copilot command not found. Install with: npm i -g @githubnext/copilot-cli
  pause
  popd
  exit /b 1
)

echo Starting Copilot CLI...
copilot %*

popd
