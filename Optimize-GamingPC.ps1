<#
.SYNOPSIS
  Safe and reversible Windows 10/11 gaming optimization script.

.DESCRIPTION
  Applies conservative performance tweaks for competitive gaming (e.g., Valorant/Rust)
  while keeping changes reversible through a backup file + restore point.

.NOTES
  - Run in an elevated PowerShell session (Run as Administrator).
  - No cheats/exploits/overclocking/security-disabling tweaks are included.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Apply','Undo')]
    [string]$Mode = 'Apply',

    [string[]]$GameExePaths = @(
        'C:\Riot Games\VALORANT\live\VALORANT.exe',
        'C:\Program Files (x86)\Steam\steamapps\common\Rust\RustClient.exe'
    ),

    [switch]$EnableTimerResolution,
    [switch]$DisableHPET,
    [switch]$SetCloudflareDNS,
    [switch]$SetGoogleDNS
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$StateDir = Join-Path $env:ProgramData 'GamingOptimizer'
$StateFile = Join-Path $StateDir 'state.json'
$RemovedAppsLog = Join-Path $StateDir 'removed-apps.txt'

function ConvertTo-Hashtable([object]$InputObject) {
    if ($null -eq $InputObject) { return @{} }
    if ($InputObject -is [hashtable]) { return $InputObject }
    $hash = @{}
    foreach ($prop in $InputObject.PSObject.Properties) {
        $hash[$prop.Name] = $prop.Value
    }
    return $hash
}


function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-StateDir {
    if (-not (Test-Path $StateDir)) {
        New-Item -Path $StateDir -ItemType Directory -Force | Out-Null
    }
}

function Save-State($state) {
    Ensure-StateDir
    $state | ConvertTo-Json -Depth 8 | Set-Content -Path $StateFile -Encoding UTF8
}

function Load-State {
    if (Test-Path $StateFile) {
        $raw = Get-Content -Raw -Path $StateFile | ConvertFrom-Json
        return [pscustomobject]@{
            Registry = ConvertTo-Hashtable $raw.Registry
            PowerScheme = ConvertTo-Hashtable $raw.PowerScheme
            Services = ConvertTo-Hashtable $raw.Services
            Tasks = ConvertTo-Hashtable $raw.Tasks
            Bcd = ConvertTo-Hashtable $raw.Bcd
            RemovedApps = @($raw.RemovedApps)
            Network = ConvertTo-Hashtable $raw.Network
        }
    }
    return [pscustomobject]@{
        Registry = @{}
        PowerScheme = @{}
        Services = @{}
        Tasks = @{}
        Bcd = @{}
        RemovedApps = @()
        Network = @{}
    }
}

function Backup-RegistryValue {
    param([string]$Path,[string]$Name,[object]$State)

    if (-not $State.Registry.ContainsKey("$Path|$Name")) {
        $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        $State.Registry["$Path|$Name"] = if ($null -ne $item) { $item.$Name } else { '__MISSING__' }
    }
}

function Set-RegistryValueSafe {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [Microsoft.Win32.RegistryValueKind]$Type,
        [object]$State
    )

    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Backup-RegistryValue -Path $Path -Name $Name -State $State
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
}

function Restore-RegistryValue {
    param([string]$Path,[string]$Name,[object]$OldValue)

    if ($OldValue -eq '__MISSING__') {
        Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    } else {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        Set-ItemProperty -Path $Path -Name $Name -Value $OldValue
    }
}

function Confirm-Action([string]$Message) {
    $response = Read-Host "$Message (Y/N)"
    return $response -match '^(Y|y)$'
}

function New-RestorePoint {
    Write-Host "Creating system restore point..."
    Checkpoint-Computer -Description 'GamingOptimizer_PreChange' -RestorePointType 'MODIFY_SETTINGS' | Out-Null
}

function Enable-UltimatePerformance {
    param([object]$State)

    $ultimate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
    $activeLine = (powercfg /getactivescheme) -join "`n"
    if (-not $State.PowerScheme.ActiveBefore) {
        if ($activeLine -match 'GUID:\s*([a-fA-F0-9\-]+)') {
            $State.PowerScheme.ActiveBefore = $Matches[1]
        }
    }

    $schemeExists = (powercfg -l) -match $ultimate
    if (-not $schemeExists) {
        powercfg -duplicatescheme $ultimate | Out-Null
    }
    powercfg -setactive $ultimate | Out-Null
    $State.PowerScheme.ActiveAfter = $ultimate
}

function Set-CPUAndPowerTuning {
    param([object]$State)

    $subProcessor = '54533251-82be-4824-96c1-47b60b740d00'
    $minProc = '893dee8e-2bef-41e0-89c6-b55d0929964c'
    $maxProc = 'bc5038f7-23e0-4960-96da-33abaf5935ec'
    $coreParkingMin = '0cc5b647-c1df-4637-891a-dec35c318583'
    $coreParkingMax = 'ea062031-0e34-4ff1-9b6d-eb1059334028'
    $subUsb = '2a737441-1930-4402-8d77-b2bebba308a3'
    $usbSuspend = '4f971e89-eebd-4455-a8de-9e59040e7347'

    $active = ((powercfg /getactivescheme) -join "`n")
    if ($active -match 'GUID:\s*([a-fA-F0-9\-]+)') {
        $scheme = $Matches[1]
        foreach ($setting in @($minProc,$maxProc,$coreParkingMin,$coreParkingMax)) {
            powercfg -setacvalueindex $scheme $subProcessor $setting 100 | Out-Null
            powercfg -setdcvalueindex $scheme $subProcessor $setting 100 | Out-Null
        }
        powercfg -setacvalueindex $scheme $subUsb $usbSuspend 0 | Out-Null
        powercfg -setdcvalueindex $scheme $subUsb $usbSuspend 0 | Out-Null
        powercfg -setactive $scheme | Out-Null
    }

    Set-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' -Name 'PowerThrottlingOff' -Value 1 -Type DWord -State $State
}

function Configure-InputLatency {
    param([object]$State, [string[]]$ExePaths)

    # Disable mouse acceleration (Enhance Pointer Precision)
    Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed' -Value '0' -Type String -State $State
    Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold1' -Value '0' -Type String -State $State
    Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold2' -Value '0' -Type String -State $State

    # Enable HAGS and Game Mode
    Set-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -Value 2 -Type DWord -State $State
    Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AllowAutoGameMode' -Value 1 -Type DWord -State $State
    Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Value 1 -Type DWord -State $State

    # Disable Fullscreen Optimizations for selected executables
    foreach ($exe in $ExePaths) {
        if (Test-Path $exe) {
            Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' -Name $exe -Value '~ DISABLEDXMAXIMIZEDWINDOWEDMODE' -Type String -State $State
        }
    }
}

function Set-TimerResolutionSession {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NtTimer {
  [DllImport("ntdll.dll", SetLastError=true)]
  public static extern uint NtSetTimerResolution(uint DesiredResolution, bool SetResolution, out uint CurrentResolution);
}
"@
    [uint32]$curr = 0
    # 5000 = 0.5 ms in 100ns units (best effort, session-only, non-persistent)
    [void][NtTimer]::NtSetTimerResolution(5000, $true, [ref]$curr)
    Write-Host "Timer resolution requested for current session only. Reverts on reboot/logoff."
}

function Configure-HPET {
    param([object]$State, [switch]$Disable)

    if (-not $Disable) { return }
    if (-not (Confirm-Action 'HPET tweak can help some systems and hurt others. Apply optional HPET tweak?')) { return }

    $current = (bcdedit /enum) -join "`n"
    if (-not $State.Bcd.useplatformclock) {
        if ($current -match 'useplatformclock\s+(Yes|No)') {
            $State.Bcd.useplatformclock = $Matches[1]
        } else {
            $State.Bcd.useplatformclock = '__MISSING__'
        }
    }

    # "Disable HPET" here means remove forced platform clock and let OS decide.
    bcdedit /deletevalue useplatformclock | Out-Null
    Write-Host 'HPET override removed. Reboot required for full effect.'
}

function Cleanup-BackgroundLoad {
    param([object]$State)

    $toStop = @('Discord','SteamWebHelper','EpicGamesLauncher','Battle.net','chrome','msedge','firefox')
    foreach ($p in $toStop) {
        Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    # Stop indexing service temporarily (startup type is preserved)
    $svc = Get-Service -Name WSearch -ErrorAction SilentlyContinue
    if ($null -ne $svc) {
        if (-not $State.Services.WSearchStartType) {
            $State.Services.WSearchStartType = (Get-CimInstance Win32_Service -Filter "Name='WSearch'").StartMode
        }
        if ($svc.Status -eq 'Running') {
            Stop-Service WSearch -Force
        }
    }

    # Disable a small set of non-critical scheduled tasks
    $tasks = @(
        '\Microsoft\XblGameSave\XblGameSaveTask',
        '\Microsoft\XblGameSave\XblGameSaveTaskLogon',
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater'
    )
    foreach ($taskPath in $tasks) {
        $taskName = Split-Path $taskPath -Leaf
        $taskFolder = ($taskPath -replace [regex]::Escape("\$taskName"),'')
        $task = Get-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -ErrorAction SilentlyContinue
        if ($null -ne $task) {
            if (-not $State.Tasks.ContainsKey($taskPath)) {
                $State.Tasks[$taskPath] = $task.State.ToString()
            }
            Disable-ScheduledTask -TaskPath $taskFolder -TaskName $taskName | Out-Null
        }
    }

    # Disable Game Bar capture overlays if user does not use it
    if (Confirm-Action 'Disable Xbox Game Bar and Game DVR capture?') {
        Set-RegistryValueSafe -Path 'HKCU:\SOFTWARE\Microsoft\GameBar' -Name 'AppCaptureEnabled' -Value 0 -Type DWord -State $State
        Set-RegistryValueSafe -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0 -Type DWord -State $State
        Set-RegistryValueSafe -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Name 'AllowGameDVR' -Value 0 -Type DWord -State $State
    }
}

function Invoke-Debloat {
    param([object]$State)

    Write-Host 'Installed AppX packages (current user):'
    Get-AppxPackage | Sort-Object Name | Select-Object Name, PackageFullName | Format-Table -AutoSize

    $removable = @(
        'Microsoft.549981C3F5F10', # Cortana
        'Microsoft.Microsoft3DViewer',
        'Microsoft.MixedReality.Portal',
        'Microsoft.Xbox.TCUI',
        'Microsoft.XboxGamingOverlay',
        'Microsoft.XboxGameOverlay',
        'Microsoft.XboxIdentityProvider',
        'Microsoft.ZuneMusic',
        'Microsoft.ZuneVideo'
    )

    if (-not (Confirm-Action 'Remove optional bloat apps listed in script?')) { return }

    Ensure-StateDir
    foreach ($name in $removable) {
        $pkgs = Get-AppxPackage -Name $name -ErrorAction SilentlyContinue
        foreach ($pkg in $pkgs) {
            "$($pkg.Name)|$($pkg.PackageFullName)|$($pkg.InstallLocation)" | Add-Content -Path $RemovedAppsLog
            $State.RemovedApps += [pscustomobject]@{ Name = $pkg.Name; PackageFullName = $pkg.PackageFullName; InstallLocation = $pkg.InstallLocation }
            Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue
        }
    }
}

function Apply-NetworkTweaks {
    param([object]$State)

    ipconfig /flushdns | Out-Null

    # Backup and disable network throttling index (multimedia scheduler tweak)
    Set-RegistryValueSafe -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'NetworkThrottlingIndex' -Value 4294967295 -Type DWord -State $State

    if ($SetCloudflareDNS -or $SetGoogleDNS) {
        if (Confirm-Action 'Apply DNS server change on active adapters?') {
            $dns = if ($SetCloudflareDNS) { @('1.1.1.1','1.0.0.1') } else { @('8.8.8.8','8.8.4.4') }
            $active = Get-DnsClient | Where-Object { $_.InterfaceAlias -notmatch 'Loopback|vEthernet' }
            foreach ($nic in $active) {
                if (-not $State.Network.ContainsKey($nic.InterfaceAlias)) {
                    $State.Network[$nic.InterfaceAlias] = (Get-DnsClientServerAddress -InterfaceAlias $nic.InterfaceAlias -AddressFamily IPv4).ServerAddresses
                }
                Set-DnsClientServerAddress -InterfaceAlias $nic.InterfaceAlias -ServerAddresses $dns
            }
        }
    }
}

function Show-GPUGuide {
    Write-Host @"
GPU driver panel recommendations (manual):
- NVIDIA Control Panel:
  * Manage 3D settings -> Power management mode -> Prefer maximum performance
  * Disable extra image scaling/sharpening filters unless you need them.
- AMD Adrenalin:
  * Gaming -> Enable Anti-Lag
  * Disable extra image scaling/sharpening features if chasing lowest latency.
"@
}

function Undo-Changes {
    $state = Load-State

    foreach ($entry in $state.Registry.GetEnumerator()) {
        $parts = $entry.Key -split '\|',2
        Restore-RegistryValue -Path $parts[0] -Name $parts[1] -OldValue $entry.Value
    }

    if ($state.PowerScheme.ActiveBefore) {
        powercfg -setactive $state.PowerScheme.ActiveBefore | Out-Null
    }

    if ($state.Services.WSearchStartType) {
        Set-Service -Name WSearch -StartupType $state.Services.WSearchStartType -ErrorAction SilentlyContinue
        Start-Service -Name WSearch -ErrorAction SilentlyContinue
    }

    foreach ($prop in $state.Tasks.GetEnumerator()) {
        $taskPath = $prop.Key
        $taskName = Split-Path $taskPath -Leaf
        $taskFolder = ($taskPath -replace [regex]::Escape("\$taskName"),'')
        Enable-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -ErrorAction SilentlyContinue | Out-Null
    }

    if ($state.Bcd.useplatformclock -eq '__MISSING__') {
        bcdedit /deletevalue useplatformclock | Out-Null
    } elseif ($state.Bcd.useplatformclock) {
        if ($state.Bcd.useplatformclock -match 'Yes') {
            bcdedit /set useplatformclock true | Out-Null
        } else {
            bcdedit /set useplatformclock false | Out-Null
        }
    }

    foreach ($nic in $state.Network.GetEnumerator()) {
        if ($nic.Value.Count -gt 0) {
            Set-DnsClientServerAddress -InterfaceAlias $nic.Key -ServerAddresses $nic.Value -ErrorAction SilentlyContinue
        } else {
            Set-DnsClientServerAddress -InterfaceAlias $nic.Key -ResetServerAddresses -ErrorAction SilentlyContinue
        }
    }

    Write-Host "Undo completed. For removed apps, use System Restore or reinstall from Microsoft Store."
}

if (-not (Test-IsAdmin)) {
    throw 'Please run this script as Administrator.'
}

if ($Mode -eq 'Undo') {
    if (-not (Confirm-Action 'Run UNDO and revert previously saved settings?')) { exit 0 }
    Undo-Changes
    exit 0
}

$state = Load-State

if (Confirm-Action 'Create restore point before applying tweaks? (recommended)') {
    New-RestorePoint
}

if (Confirm-Action 'Apply power/CPU optimizations?') {
    Enable-UltimatePerformance -State $state
    Set-CPUAndPowerTuning -State $state
}

if (Confirm-Action 'Apply input latency optimizations?') {
    Configure-InputLatency -State $state -ExePaths $GameExePaths
    if ($EnableTimerResolution) { Set-TimerResolutionSession }
    Configure-HPET -State $state -Disable:$DisableHPET
}

if (Confirm-Action 'Run background process cleanup?') {
    Cleanup-BackgroundLoad -State $state
}

if (Confirm-Action 'Run safe debloat flow? (Optional app removals)') {
    Invoke-Debloat -State $state
}

if (Confirm-Action 'Apply network latency tweaks?') {
    Apply-NetworkTweaks -State $state
}

Save-State -state $state
Show-GPUGuide

Write-Host 'All selected actions completed. Reboot is recommended.'
