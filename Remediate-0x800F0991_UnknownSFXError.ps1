#Requires -RunAsAdministrator
<#
.SYNOPSIS   Remediation – 0x800F0991  Unknown Error (-2146498159)
.DESCRIPTION
    0x800F0991 typically indicates a failure during the SFX/cab extraction phase
    of a Windows Update or SCCM package install. Root causes include:
      - Corrupt or incomplete download in SoftwareDistribution\Download
      - CBS manifest mismatch after a prior failed update attempt
      - Insufficient disk space for extraction staging
      - Windows Modules Installer (TrustedInstaller) in a bad state

    This script clears the affected staging paths, verifies disk space,
    resets TrustedInstaller, and re-triggers the update cycle.

.NOTES  Target collection: "Patch Error – UnknownError0F991 [0x800F0991]"
        Logs to: C:\Windows\Temp\PatchRemediation_0x800F0991.log
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

function Write-Log { param([string]$Msg,[string]$Level="INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts][$Level] $Msg"
    Add-Content -Path "$env:SystemRoot\Temp\PatchRemediation_0x800F0991.log" -Value "[$ts][$Level] $Msg"
}

Write-Log "──── BEGIN: 0x800F0991 Unknown Error Remediation ────"

# 1 – Check free disk space (extraction needs at least 2 GB)
Write-Log "Checking free disk space on system drive…"
$Disk = Get-PSDrive -Name ($env:SystemDrive -replace ':','') -ErrorAction SilentlyContinue
if ($Disk) {
    $FreeGB = [math]::Round($Disk.Free / 1GB, 2)
    Write-Log "Free space: ${FreeGB} GB"
    if ($FreeGB -lt 2) {
        Write-Log "WARNING: Less than 2 GB free — running Disk Cleanup first" "WARN"
        # Clean up WinSxS backup components and temp files
        cleanmgr.exe /sagerun:1 2>&1 | Out-Null
        Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# 2 – Stop services
Write-Log "Stopping wuauserv, BITS, TrustedInstaller…"
Stop-Service -Name wuauserv         -Force -ErrorAction SilentlyContinue
Stop-Service -Name BITS             -Force -ErrorAction SilentlyContinue
Stop-Service -Name TrustedInstaller -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# 3 – Clear SoftwareDistribution download cache
Write-Log "Clearing SoftwareDistribution\\Download…"
$DownPath = "$env:SystemRoot\SoftwareDistribution\Download"
if (Test-Path $DownPath) {
    Get-ChildItem $DownPath -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "SoftwareDistribution\\Download cleared."
}

# 4 – Clear CBS expansion staging folder
$CBSStagingPaths = @(
    "$env:SystemRoot\Temp\CBS",
    "$env:SystemRoot\CbsTemp"
)
foreach ($P in $CBSStagingPaths) {
    if (Test-Path $P) {
        Write-Log "Clearing CBS staging: $P"
        Get-ChildItem $P -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# 5 – Run DISM quick health check and cleanup
Write-Log "Running DISM StartComponentCleanup…"
Start-Process "DISM.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup" -Wait -NoNewWindow 2>&1 | Out-Null

Write-Log "Running DISM CheckHealth…"
$proc = Start-Process "DISM.exe" -ArgumentList "/Online /Cleanup-Image /CheckHealth" -Wait -PassThru -NoNewWindow
if ($proc.ExitCode -ne 0) {
    Write-Log "DISM reports component store issues — running RestoreHealth" "WARN"
    Start-Process "DISM.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth" -Wait -NoNewWindow
}

# 6 – Restart services
Write-Log "Restarting services…"
Start-Service -Name TrustedInstaller -ErrorAction SilentlyContinue
Start-Service -Name BITS             -ErrorAction SilentlyContinue
Start-Service -Name wuauserv         -ErrorAction SilentlyContinue
Restart-Service -Name ccmexec -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

# 7 – Trigger SCCM cycles
Write-Log "Triggering SCCM policy and update scan…"
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000021}" 2>&1 | Out-Null
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000113}" 2>&1 | Out-Null

Write-Log "──── END: 0x800F0991 Remediation Complete ────"
exit 0
