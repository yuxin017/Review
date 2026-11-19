@echo off
cd /d "%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0fix_crowdsense.ps1"
if errorlevel 1 (
  echo.
  echo Fix failed. Copy the message above into ChatGPT.
) else (
  echo.
  echo Fix complete. Stop the previous web launcher and run: .\tool\run-app.cmd
)
pause
