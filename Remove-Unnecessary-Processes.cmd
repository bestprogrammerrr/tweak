@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ============================================================================
:: Remove-Unnecessary-Processes.cmd
:: Safely closes common non-essential user applications to free CPU/RAM.
:: - Does NOT kill Windows/system-critical processes.
:: - Interactive confirmations included.
:: - Optional dry-run mode: whatif
:: ============================================================================

set "MODE=%~1"
if /I "%MODE%"=="" set "MODE=apply"
if /I not "%MODE%"=="apply" if /I not "%MODE%"=="whatif" (
  echo Usage:
  echo   %~nx0 apply
  echo   %~nx0 whatif
  exit /b 1
)

call :Header "Safe Background Process Cleanup"
if /I "%MODE%"=="whatif" (
  echo Running in WHATIF mode - no process will be terminated.
) else (
  echo Running in APPLY mode - selected processes will be terminated.
)

echo.
echo Targets are non-essential user apps only:
for %%P in (
  Discord.exe
  SteamWebHelper.exe
  EpicGamesLauncher.exe
  Battle.net.exe
  GalaxyClient.exe
  UbisoftConnect.exe
  RiotClientServices.exe
  chrome.exe
  msedge.exe
  firefox.exe
  opera.exe
  Teams.exe
  Spotify.exe
  OneDrive.exe
  Telegram.exe
  WhatsApp.exe
) do echo   - %%P

echo.
call :Confirm "Proceed with scanning and optional cleanup?" || exit /b 0

set /a FOUND=0
set /a KILLED=0

for %%P in (
  Discord.exe
  SteamWebHelper.exe
  EpicGamesLauncher.exe
  Battle.net.exe
  GalaxyClient.exe
  UbisoftConnect.exe
  RiotClientServices.exe
  chrome.exe
  msedge.exe
  firefox.exe
  opera.exe
  Teams.exe
  Spotify.exe
  OneDrive.exe
  Telegram.exe
  WhatsApp.exe
) do (
  tasklist /FI "IMAGENAME eq %%P" | find /I "%%P" >nul
  if !errorlevel! EQU 0 (
    set /a FOUND+=1
    echo.
    echo Found: %%P
    if /I "%MODE%"=="whatif" (
      echo   [WHATIF] Would terminate %%P
    ) else (
      call :Confirm "  Terminate %%P now?" && (
        taskkill /IM %%P /F >nul 2>&1
        if !errorlevel! EQU 0 (
          echo   Terminated %%P
          set /a KILLED+=1
        ) else (
          echo   Could not terminate %%P ^(may already have exited^)
        )
      )
    )
  )
)

echo.
if %FOUND% EQU 0 (
  echo No listed non-essential target processes are currently running.
) else (
  echo Scan complete. Found: %FOUND%
  if /I "%MODE%"=="whatif" (
    echo WhatIf mode: no changes applied.
  ) else (
    echo Successfully terminated: %KILLED%
  )
)

echo.
echo Tip: run this before launching Valorant/Rust for lower background load.
exit /b 0

:Header
echo.
echo ==================================================
echo %~1
echo ==================================================
exit /b 0

:Confirm
set "_ans="
set /p _ans=%~1 [Y/N]: 
if /I "%_ans%"=="Y" exit /b 0
if /I "%_ans%"=="YES" exit /b 0
exit /b 1
