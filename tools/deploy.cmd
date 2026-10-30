@echo off
REM Double-click friendly wrapper: build + install to the connected phone.
REM Any extra arguments are forwarded, e.g.  deploy.cmd -SkipBuild
setlocal
set "SCRIPT=%~dp0deploy.ps1"
where pwsh >nul 2>nul
if %ERRORLEVEL%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
)
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" (
  echo.
  echo Deploy failed with exit code %CODE%.
)
echo.
pause
exit /b %CODE%
