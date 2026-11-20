@echo off
call "%~dp0run-android.cmd" -Camera %*
exit /b %ERRORLEVEL%
