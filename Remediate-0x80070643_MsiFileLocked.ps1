#Requires -RunAsAdministrator
<#
.SYNOPSIS   Remediation – 0x80070643 MSI Fatal Error  &  0x80070020 File Locked
.DESCRIPTION
    Clears stale MSI/installer state, removes orphaned MSI temp files, resets
    Windows Installer service, and kills processes that commonly lock update
    files (Office updater, Malwarebytes, antivirus on-access scanners, etc.).
.NOTES  Target collections:
        "Patch Error – MsiInstallFailed [0x80070643]"
        "Patch Error – FileLocked       [0x80070020]"
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

function Write-Log { param([string]$Msg,[string]$Level="INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts][$Level] $Msg"
    Add-Content -Path "$env:SystemRoot\Temp\PatchRemediation_MSILock.log" -Value "[$ts][$Level] $Msg"
}

Write-Log "──── BEGIN: MSI / File-Locked Remediation ────"

# 1 – Stop Windows Installer and clear its temp state
Write-Log "Stopping Windows Installer service"
Stop-Service -Name msiserver -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# 2 – Remove orphaned MSI temp files
$MsiTempLocations = @(
    "$env:SystemRoot\Installer\*.tmp",
    "$env:TEMP\*.msi",
    "$env:TEMP\*.msp",
    "$env:SystemRoot\Temp\*.msi",
    "$env:SystemRoot\Temp\*.msp"
)
foreach ($Pattern in $MsiTempLocations) {
    $Files = Get-Item $Pattern -ErrorAction SilentlyContinue
    foreach ($F in $Files) {
        Write-Log "Removing orphaned file: $($F.FullName)"
        Remove-Item $F.FullName -Force -ErrorAction SilentlyContinue
    }
}

# 3 – Clear SCCM CCM cache for failed content
Write-Log "Clearing SCCM CCM cache"
try {
    $CCMCache = New-Object -ComObject UIResource.UIResourceMgr
    $CacheInfo = $CCMCache.GetCacheInfo()
    $CacheInfo.GetCacheElements() | ForEach-Object {
        $CacheInfo.DeleteCacheElement($_.CacheElementID)
        Write-Log "  Deleted cache element: $($_.ContentID)"
    }
} catch {
    Write-Log "COM cache clear failed, using filesystem fallback" "WARN"
    Get-ChildItem "$env:SystemRoot\CCM\Cache" -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# 4 – Identify and handle file-locking processes (0x80070020)
Write-Log "Checking for processes locking update staging area"
# SoftwareDistribution\Download is the typical locked location
$StagingPath = "$env:SystemRoot\SoftwareDistribution\Download"
$ProcsToConsider = @("OfficeClickToRun","MBAMService","MBAMAgent","ccsvchst","csc","vbc","msbuild")
foreach ($ProcName in $ProcsToConsider) {
    $Proc = Get-Process -Name $ProcName -ErrorAction SilentlyContinue
    if ($Proc) {
        Write-Log "Stopping non-critical locking process: $ProcName (PID $($Proc.Id))" "WARN"
        Stop-Process -Name $ProcName -Force -ErrorAction SilentlyContinue
    }
}

# 5 – Re-register Windows Installer
Write-Log "Re-registering msiexec"
msiexec.exe /unregserver 2>&1 | Out-Null
msiexec.exe /regserver   2>&1 | Out-Null

# 6 – Restart Windows Installer
Write-Log "Starting msiserver"
Set-Service  -Name msiserver -StartupType Manual
Start-Service -Name msiserver -ErrorAction SilentlyContinue

# 7 – Restart SCCM client
Write-Log "Restarting ccmexec"
Restart-Service -Name ccmexec -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

# 8 – Trigger re-evaluation
Write-Log "Triggering SCCM update deployment re-evaluation"
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000114}" 2>&1 | Out-Null
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000113}" 2>&1 | Out-Null

Write-Log "──── END: MSI / File-Locked Remediation Complete ────"
exit 0
