#Requires -RunAsAdministrator
<#
.SYNOPSIS   Remediation – 0x80070017 CRC Error  &  0x8007045B Shutdown In Progress
.DESCRIPTION
    0x80070017 (ERROR_CRC): Cyclic Redundancy Check failure during update
                file read. Indicates corrupted cached download on disk —
                the patch binary itself failed integrity verification.

    0x8007045B (ERROR_SHUTDOWN_IN_PROGRESS): A system shutdown was initiated
                while an update was installing. The installer was aborted mid-flight,
                potentially leaving the machine in a partial-update state.

    Actions:
      - For 0x80070017: Clear corrupt cached downloads, verify disk health,
        force re-download from DP/WSUS
      - For 0x8007045B: Clear the partial-install state, clean up CBS pending
        operations, ensure a clean restart state before re-deploying

.NOTES  Target collections:
        "Patch Error – CRCDataError      [0x80070017]"
        "Patch Error – ShutdownInProgress[0x8007045B]"
        Logs to: C:\Windows\Temp\PatchRemediation_CRC_Shutdown.log
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

function Write-Log { param([string]$Msg,[string]$Level="INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts][$Level] $Msg"
    Add-Content -Path "$env:SystemRoot\Temp\PatchRemediation_CRC_Shutdown.log" -Value "[$ts][$Level] $Msg"
}

Write-Log "──── BEGIN: CRC / Shutdown Remediation (0x80070017 / 0x8007045B) ────"

# ── PHASE 1: CRC Corrupt Download Cleanup (0x80070017) ──────────────────────

# 1 – Check disk health (CRC can indicate failing storage)
Write-Log "Running CHKDSK surface check on system volume (read-only)…"
$ChkResult = & chkdsk.exe $env:SystemDrive /scan 2>&1
$ChkResult | Select-Object -Last 5 | ForEach-Object { Write-Log "  CHKDSK: $_" }

# 2 – Stop WU services before clearing cached content
Write-Log "Stopping wuauserv and BITS…"
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Stop-Service -Name BITS     -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# 3 – Clear SoftwareDistribution download cache (corrupt CRC files live here)
Write-Log "Clearing SoftwareDistribution\\Download (corrupt CRC files)…"
$DownPath = "$env:SystemRoot\SoftwareDistribution\Download"
if (Test-Path $DownPath) {
    Get-ChildItem $DownPath -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "SoftwareDistribution\\Download cleared."
}

# 4 – Clear SCCM CCM cache (may contain corrupt cached package content)
Write-Log "Clearing SCCM CCM content cache…"
try {
    $CCMCache = New-Object -ComObject UIResource.UIResourceMgr
    $CacheInfo = $CCMCache.GetCacheInfo()
    $CacheInfo.GetCacheElements() | ForEach-Object {
        $CacheInfo.DeleteCacheElement($_.CacheElementID)
        Write-Log "  Deleted cache element: $($_.ContentID)"
    }
} catch {
    Write-Log "COM cache clear failed — using filesystem fallback" "WARN"
    Get-ChildItem "$env:SystemRoot\CCM\Cache" -Directory -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# 5 – Cancel stale BITS jobs
Write-Log "Cancelling stale BITS jobs…"
Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue | Remove-BitsTransfer -ErrorAction SilentlyContinue

# ── PHASE 2: Partial-Install Cleanup (0x8007045B) ───────────────────────────

# 6 – Clear CBS pending operations that were interrupted by shutdown
Write-Log "Checking for CBS pending operations interrupted by shutdown…"
$CBSPendingKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\SessionsPending"
if (Test-Path $CBSPendingKey) {
    Write-Log "Found CBS pending operations — clearing…" "WARN"
    Remove-Item $CBSPendingKey -Recurse -Force -ErrorAction SilentlyContinue
}

# 7 – Clear incomplete Windows Update install flags
$WUPendingKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
if (Test-Path $WUPendingKey) {
    Write-Log "Clearing WU RebootRequired flag left by aborted install…"
    Remove-Item $WUPendingKey -Recurse -Force -ErrorAction SilentlyContinue
}

# 8 – Run SFC to repair any files partially written during interrupted install
Write-Log "Running SFC /scannow to repair partially-written files…"
Start-Process "sfc.exe" -ArgumentList "/scannow" -Wait -NoNewWindow

# 9 – Restart services
Write-Log "Restarting wuauserv, BITS, ccmexec…"
Start-Service -Name BITS     -ErrorAction SilentlyContinue
Start-Service -Name wuauserv -ErrorAction SilentlyContinue
Restart-Service -Name ccmexec -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

# 10 – Trigger re-download and evaluation
Write-Log "Triggering SCCM Software Updates Scan and Deployment Evaluation…"
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000113}" 2>&1 | Out-Null
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000114}" 2>&1 | Out-Null

Write-Log "──── END: CRC / Shutdown Remediation Complete ────"
Write-Log "NOTE: If CHKDSK reported disk errors, schedule a full chkdsk /f /r at next reboot."
Write-Log "      Run: chkdsk $env:SystemDrive /f /r /x  (will run on next restart)"
exit 0
