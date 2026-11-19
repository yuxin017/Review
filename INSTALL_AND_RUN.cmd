@echo off
cd /d "%~dp0"
echo Installing CrowdSense into your FYP project...
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_crowdsense.ps1"
if errorlevel 1 (
  echo.
  echo Installation stopped safely. Read the error above.
  pause
  exit /b 1
)
echo.
echo Starting the original FYP launcher (leave this window open)...
call "%~dp0tool\run-app.cmd"
if errorlevel 1 (
  echo The FYP launcher returned an error. Check old server ports and setup.
  pause
)
