@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ============================================================================
:: Optimize-GamingPC.cmd
:: Safe + reversible Windows 10/11 gaming optimization script (CMD version)
:: No PowerShell required.
:: ============================================================================

set "STATE_DIR=%ProgramData%\GamingOptimizerCMD"
set "STATE_FILE=%STATE_DIR%\state.env"
set "LOG_FILE=%STATE_DIR%\removed-apps.txt"
set "MODE=%~1"
if /I "%MODE%"=="" set "MODE=apply"

call :RequireAdmin || exit /b 1
if not exist "%STATE_DIR%" mkdir "%STATE_DIR%" >nul 2>&1

if /I "%MODE%"=="undo" goto :UNDO
if /I not "%MODE%"=="apply" (
  echo Usage:
  echo   %~nx0 apply
  echo   %~nx0 undo
  exit /b 1
)

call :Header "Windows Gaming Optimization (CMD)"
call :Confirm "Create restore point before changes (recommended)?" || goto :SKIP_RESTORE
call :CreateRestorePoint
:SKIP_RESTORE

call :Confirm "Apply power + CPU optimizations?" && call :ApplyPower
call :Confirm "Apply input latency tweaks?" && call :ApplyInput
call :Confirm "Run background cleanup tweaks?" && call :ApplyBackground
call :Confirm "Run safe app cleanup (winget optional removals)?" && call :ApplyDebloat
call :Confirm "Apply network latency tweaks?" && call :ApplyNetwork

call :WriteState
call :GpuGuide

echo.
echo Done. Reboot recommended.
exit /b 0

:UNDO
call :Header "Undo Gaming Optimization (CMD)"
if not exist "%STATE_FILE%" (
  echo No state file found: "%STATE_FILE%"
  echo Nothing to undo.
  exit /b 1
)
call :Confirm "Revert settings captured in state file?" || exit /b 0
call "%STATE_FILE%"

:: Restore power scheme
if defined PREV_ACTIVE_SCHEME powercfg /setactive %PREV_ACTIVE_SCHEME% >nul 2>&1

:: Restore registry values
call :RestoreReg "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" "%REG_PowerThrottlingOff%"
call :RestoreReg "HKCU\Control Panel\Mouse" "MouseSpeed" "%REG_MouseSpeed%"
call :RestoreReg "HKCU\Control Panel\Mouse" "MouseThreshold1" "%REG_MouseThreshold1%"
call :RestoreReg "HKCU\Control Panel\Mouse" "MouseThreshold2" "%REG_MouseThreshold2%"
call :RestoreReg "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" "%REG_HwSchMode%"
call :RestoreReg "HKCU\Software\Microsoft\GameBar" "AllowAutoGameMode" "%REG_AllowAutoGameMode%"
call :RestoreReg "HKCU\Software\Microsoft\GameBar" "AutoGameModeEnabled" "%REG_AutoGameModeEnabled%"
call :RestoreReg "HKCU\SOFTWARE\Microsoft\GameBar" "AppCaptureEnabled" "%REG_AppCaptureEnabled%"
call :RestoreReg "HKCU\System\GameConfigStore" "GameDVR_Enabled" "%REG_GameDVR_Enabled%"
call :RestoreReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" "%REG_AllowGameDVR%"
call :RestoreReg "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" "%REG_NetworkThrottlingIndex%"

:: Restore search service
if /I "%WSEARCH_START%"=="AUTO" sc config WSearch start= auto >nul 2>&1
if /I "%WSEARCH_START%"=="DEMAND" sc config WSearch start= demand >nul 2>&1
if /I "%WSEARCH_START%"=="DISABLED" sc config WSearch start= disabled >nul 2>&1
if /I "%WSEARCH_WAS_RUNNING%"=="1" net start WSearch >nul 2>&1

:: Re-enable tasks we disabled
schtasks /Change /TN "\Microsoft\XblGameSave\XblGameSaveTask" /ENABLE >nul 2>&1
schtasks /Change /TN "\Microsoft\XblGameSave\XblGameSaveTaskLogon" /ENABLE >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\Application Experience\ProgramDataUpdater" /ENABLE >nul 2>&1

:: Restore BCDEdit useplatformclock if we touched it
if /I "%BCD_USEPLATFORMCLOCK%"=="MISSING" bcdedit /deletevalue useplatformclock >nul 2>&1
if /I "%BCD_USEPLATFORMCLOCK%"=="Yes" bcdedit /set useplatformclock true >nul 2>&1
if /I "%BCD_USEPLATFORMCLOCK%"=="No" bcdedit /set useplatformclock false >nul 2>&1

:: Restore DNS for all enabled adapters if we captured values
if defined DNS_BACKUP_FILE if exist "%DNS_BACKUP_FILE%" netsh exec "%DNS_BACKUP_FILE%" >nul 2>&1

echo Undo complete. Reboot recommended.
exit /b 0

:ApplyPower
call :CaptureActiveScheme
powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 >nul 2>&1
powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61 >nul 2>&1
for %%S in (
  893dee8e-2bef-41e0-89c6-b55d0929964c
  bc5038f7-23e0-4960-96da-33abaf5935ec
  0cc5b647-c1df-4637-891a-dec35c318583
  ea062031-0e34-4ff1-9b6d-eb1059334028
) do (
  powercfg /setacvalueindex scheme_current 54533251-82be-4824-96c1-47b60b740d00 %%S 100 >nul 2>&1
  powercfg /setdcvalueindex scheme_current 54533251-82be-4824-96c1-47b60b740d00 %%S 100 >nul 2>&1
)
powercfg /setacvalueindex scheme_current 2a737441-1930-4402-8d77-b2bebba308a3 4f971e89-eebd-4455-a8de-9e59040e7347 0 >nul 2>&1
powercfg /setdcvalueindex scheme_current 2a737441-1930-4402-8d77-b2bebba308a3 4f971e89-eebd-4455-a8de-9e59040e7347 0 >nul 2>&1
powercfg /setactive scheme_current >nul 2>&1
call :BackupReg "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" REG_PowerThrottlingOff
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" /v "PowerThrottlingOff" /t REG_DWORD /d 1 /f >nul
exit /b 0

:ApplyInput
call :BackupReg "HKCU\Control Panel\Mouse" "MouseSpeed" REG_MouseSpeed
call :BackupReg "HKCU\Control Panel\Mouse" "MouseThreshold1" REG_MouseThreshold1
call :BackupReg "HKCU\Control Panel\Mouse" "MouseThreshold2" REG_MouseThreshold2
reg add "HKCU\Control Panel\Mouse" /v MouseSpeed /t REG_SZ /d 0 /f >nul
reg add "HKCU\Control Panel\Mouse" /v MouseThreshold1 /t REG_SZ /d 0 /f >nul
reg add "HKCU\Control Panel\Mouse" /v MouseThreshold2 /t REG_SZ /d 0 /f >nul

call :BackupReg "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" REG_HwSchMode
reg add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v HwSchMode /t REG_DWORD /d 2 /f >nul

call :BackupReg "HKCU\Software\Microsoft\GameBar" "AllowAutoGameMode" REG_AllowAutoGameMode
call :BackupReg "HKCU\Software\Microsoft\GameBar" "AutoGameModeEnabled" REG_AutoGameModeEnabled
reg add "HKCU\Software\Microsoft\GameBar" /v AllowAutoGameMode /t REG_DWORD /d 1 /f >nul
reg add "HKCU\Software\Microsoft\GameBar" /v AutoGameModeEnabled /t REG_DWORD /d 1 /f >nul

call :Confirm "Disable Xbox Game Bar / DVR capture?" && (
  call :BackupReg "HKCU\SOFTWARE\Microsoft\GameBar" "AppCaptureEnabled" REG_AppCaptureEnabled
  call :BackupReg "HKCU\System\GameConfigStore" "GameDVR_Enabled" REG_GameDVR_Enabled
  call :BackupReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" REG_AllowGameDVR
  reg add "HKCU\SOFTWARE\Microsoft\GameBar" /v AppCaptureEnabled /t REG_DWORD /d 0 /f >nul
  reg add "HKCU\System\GameConfigStore" /v GameDVR_Enabled /t REG_DWORD /d 0 /f >nul
  reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" /v AllowGameDVR /t REG_DWORD /d 0 /f >nul
)

call :Confirm "Optional HPET tweak (can help or hurt): remove forced platform clock?" && call :ApplyHPET
exit /b 0

:ApplyHPET
for /f "tokens=1,2" %%A in ('bcdedit /enum ^| findstr /I "useplatformclock"') do set "_upc=%%B"
if not defined _upc (set "BCD_USEPLATFORMCLOCK=MISSING") else set "BCD_USEPLATFORMCLOCK=%_upc%"
bcdedit /deletevalue useplatformclock >nul 2>&1
exit /b 0

:ApplyBackground
for %%P in (Discord.exe SteamWebHelper.exe EpicGamesLauncher.exe Battle.net.exe chrome.exe msedge.exe firefox.exe) do taskkill /IM %%P /F >nul 2>&1
for /f "tokens=3" %%S in ('sc qc WSearch ^| findstr /I "START_TYPE"') do set "WSEARCH_START=%%S"
sc query WSearch | findstr /I "RUNNING" >nul && set "WSEARCH_WAS_RUNNING=1"
net stop WSearch >nul 2>&1
schtasks /Change /TN "\Microsoft\XblGameSave\XblGameSaveTask" /DISABLE >nul 2>&1
schtasks /Change /TN "\Microsoft\XblGameSave\XblGameSaveTaskLogon" /DISABLE >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\Application Experience\ProgramDataUpdater" /DISABLE >nul 2>&1
exit /b 0

:ApplyDebloat
where winget >nul 2>&1 || (
  echo winget not found. Skipping optional app removals.
  exit /b 0
)
(
  echo Microsoft Teams
  echo Cortana
  echo Mixed Reality Portal
  echo 3D Viewer
  echo Xbox Game Bar
)> "%STATE_DIR%\removal-candidates.txt"

call :Confirm "Remove optional apps with winget (safe list only)?" || exit /b 0
for %%A in ("Microsoft Teams" "Cortana" "Mixed Reality Portal" "3D Viewer" "Xbox Game Bar") do (
  echo Removing %%~A>>"%LOG_FILE%"
  winget uninstall --name %%~A --silent --accept-source-agreements >nul 2>&1
)
exit /b 0

:ApplyNetwork
ipconfig /flushdns >nul 2>&1
call :BackupReg "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" REG_NetworkThrottlingIndex
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex /t REG_DWORD /d 4294967295 /f >nul

call :Confirm "Set DNS to Cloudflare (1.1.1.1 / 1.0.0.1)?" && (
  set "DNS_BACKUP_FILE=%STATE_DIR%\dns-backup.txt"
  netsh -c interface dump > "%DNS_BACKUP_FILE%"
  for /f "tokens=1,2,3,4,*" %%a in ('netsh interface ipv4 show interfaces ^| findstr /R "^[ ]*[0-9]"') do (
    netsh interface ipv4 set dns name="%%e" static 1.1.1.1 primary validate=no >nul 2>&1
    netsh interface ipv4 add dns name="%%e" 1.0.0.1 index=2 validate=no >nul 2>&1
  )
)
exit /b 0

:WriteState
(
  echo @echo off
  if defined PREV_ACTIVE_SCHEME echo set "PREV_ACTIVE_SCHEME=%PREV_ACTIVE_SCHEME%"
  if defined REG_PowerThrottlingOff echo set "REG_PowerThrottlingOff=%REG_PowerThrottlingOff%"
  if defined REG_MouseSpeed echo set "REG_MouseSpeed=%REG_MouseSpeed%"
  if defined REG_MouseThreshold1 echo set "REG_MouseThreshold1=%REG_MouseThreshold1%"
  if defined REG_MouseThreshold2 echo set "REG_MouseThreshold2=%REG_MouseThreshold2%"
  if defined REG_HwSchMode echo set "REG_HwSchMode=%REG_HwSchMode%"
  if defined REG_AllowAutoGameMode echo set "REG_AllowAutoGameMode=%REG_AllowAutoGameMode%"
  if defined REG_AutoGameModeEnabled echo set "REG_AutoGameModeEnabled=%REG_AutoGameModeEnabled%"
  if defined REG_AppCaptureEnabled echo set "REG_AppCaptureEnabled=%REG_AppCaptureEnabled%"
  if defined REG_GameDVR_Enabled echo set "REG_GameDVR_Enabled=%REG_GameDVR_Enabled%"
  if defined REG_AllowGameDVR echo set "REG_AllowGameDVR=%REG_AllowGameDVR%"
  if defined REG_NetworkThrottlingIndex echo set "REG_NetworkThrottlingIndex=%REG_NetworkThrottlingIndex%"
  if defined WSEARCH_START echo set "WSEARCH_START=%WSEARCH_START%"
  if defined WSEARCH_WAS_RUNNING echo set "WSEARCH_WAS_RUNNING=%WSEARCH_WAS_RUNNING%"
  if defined BCD_USEPLATFORMCLOCK echo set "BCD_USEPLATFORMCLOCK=%BCD_USEPLATFORMCLOCK%"
  if defined DNS_BACKUP_FILE echo set "DNS_BACKUP_FILE=%DNS_BACKUP_FILE%"
) > "%STATE_FILE%"
exit /b 0

:BackupReg
set "%~3=__MISSING__"
for /f "skip=2 tokens=1,2,*" %%a in ('reg query "%~1" /v "%~2" 2^>nul') do set "%~3=%%c"
exit /b 0

:RestoreReg
if /I "%~3"=="__MISSING__" (
  reg delete "%~1" /v "%~2" /f >nul 2>&1
) else (
  reg add "%~1" /v "%~2" /t REG_SZ /d "%~3" /f >nul 2>&1
)
exit /b 0

:CaptureActiveScheme
for /f "tokens=3" %%G in ('powercfg /getactivescheme') do set "PREV_ACTIVE_SCHEME=%%G"
exit /b 0

:CreateRestorePoint
wmic /Namespace:\\root\default Path SystemRestore Call CreateRestorePoint "GamingOptimizerCMD_PreChange", 100, 7 >nul 2>&1
if errorlevel 1 echo Could not create restore point (System Protection may be off).
exit /b 0

:GpuGuide
echo.
echo GPU guide ^(manual^):
echo   NVIDIA Control Panel ^> Manage 3D settings ^> Power management mode ^> Prefer maximum performance
echo   AMD Adrenalin ^> Gaming ^> Enable Anti-Lag
echo   Disable unnecessary scaling/sharpening features for lowest latency.
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

:RequireAdmin
net session >nul 2>&1
if errorlevel 1 (
  echo Please run this script as Administrator.
  exit /b 1
)
exit /b 0
