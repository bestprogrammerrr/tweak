@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ============================================================================
:: Remove-Unnecessary-System-Apps.cmd
:: Safe, interactive removal of optional/non-essential Windows apps.
:: - Uses winget where available.
:: - Creates restore point attempt + logs removals.
:: - Does NOT target Microsoft Store, Edge WebView, or core components.
:: ============================================================================

set "MODE=%~1"
if /I "%MODE%"=="" set "MODE=list"

set "STATE_DIR=%ProgramData%\GamingOptimizerCMD"
set "LOG_FILE=%STATE_DIR%\removed-system-apps.txt"
if not exist "%STATE_DIR%" mkdir "%STATE_DIR%" >nul 2>&1

call :RequireAdmin || exit /b 1
where winget >nul 2>&1 || (
  echo winget is not available on this PC.
  echo Install/update App Installer from Microsoft Store and run again.
  exit /b 1
)

if /I "%MODE%"=="list" goto :LIST
if /I "%MODE%"=="remove" goto :REMOVE

echo Usage:
echo   %~nx0 list
echo   %~nx0 remove
exit /b 1

:LIST
call :Header "Optional app list (safe candidates)"
call :PrintCandidates
echo.
echo Tip: run "%~nx0 remove" to uninstall interactively.
exit /b 0

:REMOVE
call :Header "Safe removal of optional system apps"
call :PrintCandidates

echo.
call :Confirm "Create restore point before uninstalling? (recommended)" && call :CreateRestorePoint

echo.
call :Confirm "Proceed with interactive app removal?" || exit /b 0

echo --- %date% %time% --- >> "%LOG_FILE%"
set /a REMOVED=0

for %%A in (
  "Microsoft Teams|Microsoft.Teams"
  "Cortana|Microsoft.549981C3F5F10"
  "Mixed Reality Portal|Microsoft.MixedReality.Portal"
  "3D Viewer|Microsoft.Microsoft3DViewer"
  "Xbox Console Companion|Microsoft.XboxApp"
  "Xbox Game Bar|Microsoft.XboxGamingOverlay"
  "Movies ^& TV|Microsoft.ZuneVideo"
  "Groove Music|Microsoft.ZuneMusic"
  "Solitaire Collection|Microsoft.MicrosoftSolitaireCollection"
  "Clipchamp|Clipchamp.Clipchamp"
) do (
  for /f "tokens=1,2 delims=|" %%N in (%%A) do (
    call :TryRemove "%%~N" "%%~O"
  )
)

echo.
echo Removal pass finished. Removed: %REMOVED%
echo Log file: "%LOG_FILE%"
echo You can reinstall any removed app from Microsoft Store.
exit /b 0

:TryRemove
set "APP_NAME=%~1"
set "APP_ID=%~2"

winget list --id "%APP_ID%" --exact >nul 2>&1
if errorlevel 1 (
  goto :eof
)

echo.
echo Found: %APP_NAME% (%APP_ID%)
call :Confirm "  Uninstall this app?" || goto :eof

winget uninstall --id "%APP_ID%" --exact --silent --accept-source-agreements >nul 2>&1
if errorlevel 1 (
  echo   Failed to uninstall %APP_NAME% >> "%LOG_FILE%"
  echo   Could not uninstall %APP_NAME%
) else (
  echo   Removed %APP_NAME% (%APP_ID%) >> "%LOG_FILE%"
  echo   Removed %APP_NAME%
  set /a REMOVED+=1
)
goto :eof

:PrintCandidates
echo This script only targets optional apps, NOT core system components.
echo Excluded intentionally: Microsoft Store, Edge WebView, and system-critical packages.
echo.
echo Candidates:
echo   - Microsoft Teams
echo   - Cortana
echo   - Mixed Reality Portal
echo   - 3D Viewer
echo   - Xbox Console Companion
echo   - Xbox Game Bar
echo   - Movies ^& TV
echo   - Groove Music
echo   - Microsoft Solitaire Collection
echo   - Clipchamp
exit /b 0

:CreateRestorePoint
wmic /Namespace:\\root\default Path SystemRestore Call CreateRestorePoint "RemoveOptionalApps_PreChange", 100, 7 >nul 2>&1
if errorlevel 1 (
  echo Could not create restore point (System Protection may be off).
) else (
  echo Restore point created.
)
exit /b 0

:Confirm
set "_ans="
set /p _ans=%~1 [Y/N]: 
if /I "%_ans%"=="Y" exit /b 0
if /I "%_ans%"=="YES" exit /b 0
exit /b 1

:RequireAdmin
net session >nul 2>&1
if errorlevel 1 (
  echo Please run this script as Administrator.
  exit /b 1
)
exit /b 0

:Header
echo.
echo ==================================================
echo %~1
echo ==================================================
exit /b 0
