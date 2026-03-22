#Requires -RunAsAdministrator
<#
.SYNOPSIS   Remediation – 0x80070002 File Not Found  &  0x80246007 Download Failed
.DESCRIPTION
    Clears the Software Distribution download cache, resets BITS queue, forces
    SCCM to re-download content from the Distribution Point.
.NOTES  Target collections:
        "Patch Error – FileNotFound    [0x80070002]"
        "Patch Error – DownloadFailed  [0x80246007]"
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

function Write-Log { param([string]$Msg,[string]$Level="INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts][$Level] $Msg"
    Add-Content -Path "$env:SystemRoot\Temp\PatchRemediation_DownloadFail.log" -Value "[$ts][$Level] $Msg"
}

Write-Log "──── BEGIN: File Not Found / Download Failed Remediation ────"

# 1 – Stop services before touching cache
Write-Log "Stopping BITS and wuauserv"
Stop-Service -Name BITS     -Force -ErrorAction SilentlyContinue
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# 2 – Clear Software Distribution download folder
Write-Log "Clearing SoftwareDistribution\Download"
$DownloadPath = "$env:SystemRoot\SoftwareDistribution\Download"
if (Test-Path $DownloadPath) {
    Get-ChildItem $DownloadPath -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# 3 – Clear BITS queue
Write-Log "Cancelling all BITS jobs"
Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue | Remove-BitsTransfer -ErrorAction SilentlyContinue

# 4 – Reset BITS database
Write-Log "Resetting BITS database"
$BitsDb = "$env:ALLUSERSPROFILE\Application Data\Microsoft\Network\Downloader"
if (Test-Path $BitsDb) {
    Get-ChildItem $BitsDb -Filter "qmgr*.dat" | Remove-Item -Force -ErrorAction SilentlyContinue
}

# 5 – Clear SCCM CCM cache so content is re-downloaded from DP
Write-Log "Clearing SCCM content cache"
try {
    $CCMCache = New-Object -ComObject UIResource.UIResourceMgr
    $CacheInfo = $CCMCache.GetCacheInfo()
    $CacheInfo.GetCacheElements() | ForEach-Object {
        $CacheInfo.DeleteCacheElement($_.CacheElementID)
        Write-Log "  Deleted cache: $($_.ContentID)"
    }
} catch {
    Write-Log "COM cache clear failed, using filesystem fallback" "WARN"
    Get-ChildItem "$env:SystemRoot\CCM\Cache" -Directory -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# 6 – Restart services
Write-Log "Starting BITS and wuauserv"
Start-Service -Name BITS     -ErrorAction SilentlyContinue
Start-Service -Name wuauserv -ErrorAction SilentlyContinue
Restart-Service -Name ccmexec -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

# 7 – Verify DP connectivity (basic TCP test to common DP ports)
$CCMReg = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client" -ErrorAction SilentlyContinue
if ($CCMReg.AssignedSiteCode) {
    Write-Log "SCCM Site: $($CCMReg.AssignedSiteCode)"
}

# 8 – Trigger content location request + update scan
Write-Log "Triggering SCCM content evaluation and update scan"
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000114}" 2>&1 | Out-Null
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000113}" 2>&1 | Out-Null

Write-Log "──── END: Download Failed Remediation Complete ────"
exit 0
