#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Master SCCM Patch Error Remediation Dispatcher

.DESCRIPTION
    Detects the last Windows Update / SCCM patch error on the local machine,
    maps it to the correct remediation script, and executes it.
    All output is logged to C:\Windows\Temp\PatchRemediation_Master.log.

    Covers 29 error codes across 16 individual remediation scripts:

      Script                                      Handles
      ----                                        -------
      Remediate-0x80070005_AccessDenied           0x80070005
      Remediate-0x80070422_WUServiceDisabled      0x80070422, 0x87D00324
      Remediate-0x8024402C_WsusConnectFail        0x8024402C, 0x80244022, 0xC1800118
      Remediate-0x80070BC9_RebootPending          0x80070BC9, 0x80070BC2
      Remediate-0x80073712_CBSCorrupt             0x80073712, 0x8007371B
      Remediate-0x80070643_MsiFileLocked          0x80070643, 0x80070020
      Remediate-0x80070002_DownloadFailed         0x80070002, 0x80246007
      Remediate-0x800B0109_CertChainUntrusted     0x800B0109
      Remediate-0x800705B4_TimeoutWuaError        0x800705B4, 0x80240FFF, 0x80240010,
                                                  0x80240022, 0x8007000E
      Remediate-0x80D02002_DeliveryOptimization   0x80D02002, 0x80D03805
      Remediate-0x800F0991_UnknownSFXError        0x800F0991
      Remediate-0x87D00664_UpdatesHandlerJob      0x87D00664, 0x87D00665
      Remediate-0x800705B9_XmlParseError          0x800705B9
      Remediate-0x8007139F_InvalidState           0x8007139F
      Remediate-0x80070017_CRC_Shutdown           0x80070017, 0x8007045B

.PARAMETER ErrorCode
    Optional hex error code to force (e.g. "0x80070422").
    When omitted the script auto-detects from WMI (CCM_SoftwareUpdate) with
    a fallback to the Windows Update registry.

.PARAMETER ScriptRoot
    Folder that contains the individual Remediate-*.ps1 scripts.
    Defaults to the directory containing this script ($PSScriptRoot).

.PARAMETER LogPath
    Master log file path.
    Default: C:\Windows\Temp\PatchRemediation_Master.log

.EXAMPLE
    # Auto-detect and remediate
    .\SCCM_Master-PatchRemediation.ps1

.EXAMPLE
    # Force a specific error code
    .\SCCM_Master-PatchRemediation.ps1 -ErrorCode "0x80D02002"

.EXAMPLE
    # Scripts live on a UNC share (SCCM Package source)
    .\SCCM_Master-PatchRemediation.ps1 `
        -ErrorCode  "0x87D00664" `
        -ScriptRoot "\\SCCM01\Sources\Remediation\PatchErrors"

.NOTES
    Author   : IT Engineering
    Version  : 2.0
    Requires : PowerShell 5.1 | Run as SYSTEM or local Administrator
    Deploy   : SCCM Package targeting each Patch Error collection with the
               appropriate -ErrorCode argument per Program definition.
#>

[CmdletBinding()]
param(
    [string]$ErrorCode  = "",
    [string]$ScriptRoot = $PSScriptRoot,
    [string]$LogPath    = "$env:SystemRoot\Temp\PatchRemediation_Master.log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

# =============================================================================
# Logging
# =============================================================================
function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts][$Level] $Msg"
    $color = switch ($Level) {
        "ERROR"   { "Red"     }
        "WARN"    { "Yellow"  }
        "SUCCESS" { "Green"   }
        default   { "Cyan"    }
    }
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
}

# =============================================================================
# Error code -> remediation script mapping  (29 codes, 15 scripts)
# =============================================================================
$RemediationMap = @{

    # Access denied / permissions
    "0x80070005" = @{ Script = "Remediate-0x80070005_AccessDenied.ps1"
                      Desc   = "Access Denied - WUA/SCCM permission failure" }

    # Windows Update service disabled / SCCM policy issues
    "0x80070422" = @{ Script = "Remediate-0x80070422_WUServiceDisabled.ps1"
                      Desc   = "Windows Update Service Disabled" }
    "0x87D00324" = @{ Script = "Remediate-0x80070422_WUServiceDisabled.ps1"
                      Desc   = "App Not Detected / SCCM Policy Not Received" }

    # WSUS / SUP connectivity
    "0x8024402C" = @{ Script = "Remediate-0x8024402C_WsusConnectFail.ps1"
                      Desc   = "WSUS Connection Failure - proxy/DNS" }
    "0x80244022" = @{ Script = "Remediate-0x8024402C_WsusConnectFail.ps1"
                      Desc   = "WSUS HTTP 503 Service Unavailable" }
    "0xC1800118" = @{ Script = "Remediate-0x8024402C_WsusConnectFail.ps1"
                      Desc   = "Update Declined on WSUS Server" }

    # Reboot states
    "0x80070BC9" = @{ Script = "Remediate-0x80070BC9_RebootPending.ps1"
                      Desc   = "Reboot Pending - blocking installs" }
    "0x80070BC2" = @{ Script = "Remediate-0x80070BC9_RebootPending.ps1"
                      Desc   = "Reboot Required - update installed, reboot needed" }

    # CBS / Component Store corruption
    "0x80073712" = @{ Script = "Remediate-0x80073712_CBSCorrupt.ps1"
                      Desc   = "CBS/Component Store Corruption" }
    "0x8007371B" = @{ Script = "Remediate-0x80073712_CBSCorrupt.ps1"
                      Desc   = "CBS Transaction/Manifest Error" }

    # MSI installer / file lock
    "0x80070643" = @{ Script = "Remediate-0x80070643_MsiFileLocked.ps1"
                      Desc   = "MSI Fatal Install Error" }
    "0x80070020" = @{ Script = "Remediate-0x80070643_MsiFileLocked.ps1"
                      Desc   = "File Locked by Another Process" }

    # File not found / download / BITS / DP failures
    "0x80070002" = @{ Script = "Remediate-0x80070002_DownloadFailed.ps1"
                      Desc   = "Source File Not Found" }
    "0x80246007" = @{ Script = "Remediate-0x80070002_DownloadFailed.ps1"
                      Desc   = "Content Download Failed from DP" }

    # Certificate trust / PKI
    "0x800B0109" = @{ Script = "Remediate-0x800B0109_CertChainUntrusted.ps1"
                      Desc   = "Untrusted Certificate Chain" }

    # Timeout / unexpected WUA / memory / cancelled
    "0x800705B4" = @{ Script = "Remediate-0x800705B4_TimeoutWuaError.ps1"
                      Desc   = "Operation Timeout" }
    "0x80240FFF" = @{ Script = "Remediate-0x800705B4_TimeoutWuaError.ps1"
                      Desc   = "Unexpected WUA Agent Error" }
    "0x80240010" = @{ Script = "Remediate-0x800705B4_TimeoutWuaError.ps1"
                      Desc   = "Update Cancelled by Policy/User" }
    "0x80240022" = @{ Script = "Remediate-0x800705B4_TimeoutWuaError.ps1"
                      Desc   = "All Updates Not Applicable - scan/policy mismatch" }
    "0x8007000E" = @{ Script = "Remediate-0x800705B4_TimeoutWuaError.ps1"
                      Desc   = "Insufficient Memory During Update Processing" }

    # Delivery Optimization  (IT Engineering live environment)
    "0x80D02002" = @{ Script = "Remediate-0x80D02002_DeliveryOptimization.ps1"
                      Desc   = "Delivery Optimization Download Stalled" }
    "0x80D03805" = @{ Script = "Remediate-0x80D02002_DeliveryOptimization.ps1"
                      Desc   = "Delivery Optimization Unknown Internal Error" }

    # SFX/cab extraction / TrustedInstaller failure
    "0x800F0991" = @{ Script = "Remediate-0x800F0991_UnknownSFXError.ps1"
                      Desc   = "Unknown Error - SFX/cab extraction or CBS manifest mismatch" }

    # SCCM handler job errors  (IT Engineering live environment)
    "0x87D00664" = @{ Script = "Remediate-0x87D00664_UpdatesHandlerJob.ps1"
                      Desc   = "SCCM Updates Handler Job Cancelled" }
    "0x87D00665" = @{ Script = "Remediate-0x87D00664_UpdatesHandlerJob.ps1"
                      Desc   = "No Updates to Process in SCCM Handler Job" }

    # XML parse error / corrupt DataStore.edb  (IT Engineering live environment)
    "0x800705B9" = @{ Script = "Remediate-0x800705B9_XmlParseError.ps1"
                      Desc   = "XML Parse Error - corrupt DataStore.edb or malformed WSUS response" }

    # Invalid resource/service state  (IT Engineering live environment)
    "0x8007139F" = @{ Script = "Remediate-0x8007139F_InvalidState.ps1"
                      Desc   = "Group or Resource Not in Correct State" }

    # CRC data error / shutdown-interrupted install  (IT Engineering live environment)
    "0x80070017" = @{ Script = "Remediate-0x80070017_CRC_Shutdown.ps1"
                      Desc   = "CRC Data Error - corrupt cached download" }
    "0x8007045B" = @{ Script = "Remediate-0x80070017_CRC_Shutdown.ps1"
                      Desc   = "System Shutdown In Progress - install was interrupted" }
}

# =============================================================================
# Banner
# =============================================================================
Write-Log "================================================================"
Write-Log "  IT Engineering - SCCM Patch Error Remediation Dispatcher  v2.0"
Write-Log "  Host     : $env:COMPUTERNAME"
Write-Log "  User     : $env:USERNAME"
Write-Log "  Time     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "  Scripts  : $ScriptRoot"
Write-Log "================================================================"

# =============================================================================
# Auto-detect error code if not supplied
# =============================================================================
if ([string]::IsNullOrEmpty($ErrorCode)) {
    Write-Log "No -ErrorCode supplied. Auto-detecting from WMI..."

    # Primary: CCM_SoftwareUpdate (most accurate - SCCM-reported error)
    try {
        $SccmError = Get-WmiObject -Namespace "root\ccm\clientsdk" `
                                   -Class "CCM_SoftwareUpdate" `
                                   -ErrorAction Stop |
            Where-Object { $_.ErrorCode -and $_.ErrorCode -ne 0 } |
            Sort-Object EvaluationState -Descending |
            Select-Object -First 1

        if ($SccmError) {
            $ErrorCode = "0x{0:X8}" -f ([uint32]$SccmError.ErrorCode)
            Write-Log "Detected via CCM_SoftwareUpdate: $ErrorCode (decimal: $($SccmError.ErrorCode))"
        }
    }
    catch {
        Write-Log "CCM_SoftwareUpdate query failed: $_" "WARN"
    }

    # Fallback: Windows Update registry
    if ([string]::IsNullOrEmpty($ErrorCode)) {
        $WuReg = Get-ItemProperty `
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Install" `
            -ErrorAction SilentlyContinue
        if ($WuReg -and $WuReg.LastError -and $WuReg.LastError -ne 0) {
            $ErrorCode = "0x{0:X8}" -f ([uint32]$WuReg.LastError)
            Write-Log "Detected via WU registry: $ErrorCode"
        }
    }

    if ([string]::IsNullOrEmpty($ErrorCode)) {
        Write-Log "No patch error detected on this machine. Nothing to remediate." "WARN"
        exit 0
    }
}

# =============================================================================
# Normalise error code format -> 0xXXXXXXXX uppercase
# =============================================================================
$ErrorCode = $ErrorCode.Trim().ToUpper()
if (-not $ErrorCode.StartsWith("0X")) { $ErrorCode = "0X" + $ErrorCode }
$hex       = $ErrorCode.Substring(2).TrimStart("0").PadLeft(8, "0").ToUpper()
$ErrorCode = "0x$hex"

Write-Log "Target error code: $ErrorCode"

# =============================================================================
# Skip if success
# =============================================================================
if ($ErrorCode -eq "0x00000000") {
    Write-Log "Error code is 0x00000000 (SUCCESS). No remediation required." "SUCCESS"
    exit 0
}

# =============================================================================
# Look up remediation
# =============================================================================
if (-not $RemediationMap.ContainsKey($ErrorCode)) {
    Write-Log "No specific remediation mapped for $ErrorCode." "WARN"
    Write-Log "Running generic WUA reset as fallback..." "WARN"

    # Generic fallback - full WUA/SoftwareDistribution reset
    Stop-Service -Name wuauserv, BITS -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    foreach ($Dir in @("$env:SystemRoot\SoftwareDistribution\DataStore",
                       "$env:SystemRoot\SoftwareDistribution\Download")) {
        if (Test-Path $Dir) {
            Get-ChildItem $Dir -Recurse -Force |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Cleared: $Dir"
        }
    }

    Start-Service -Name wuauserv, BITS -ErrorAction SilentlyContinue
    Restart-Service -Name ccmexec -Force -ErrorAction SilentlyContinue
    Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client `
        -Name TriggerSchedule `
        -ArgumentList "{00000000-0000-0000-0000-000000000113}" 2>&1 | Out-Null

    Write-Log "Generic fallback remediation complete." "SUCCESS"
    exit 0
}

$Remediation = $RemediationMap[$ErrorCode]
Write-Log "Matched: $($Remediation.Desc)"
Write-Log "Script : $($Remediation.Script)"

# =============================================================================
# Locate and execute remediation script
# =============================================================================
$ScriptPath = Join-Path $ScriptRoot $Remediation.Script

if (-not (Test-Path $ScriptPath)) {
    Write-Log "Remediation script not found: $ScriptPath" "ERROR"
    Write-Log "Ensure all Remediate-*.ps1 files are in: $ScriptRoot" "ERROR"
    exit 1
}

Write-Log "----------------------------------------------------------------"
Write-Log "Executing: $ScriptPath"
Write-Log "----------------------------------------------------------------"

try {
    & $ScriptPath
    $ExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }

    if ($ExitCode -eq 0) {
        Write-Log "Remediation completed successfully (exit 0)." "SUCCESS"
    } else {
        Write-Log "Remediation script exited with code: $ExitCode" "WARN"
    }
}
catch {
    Write-Log "Remediation script threw an exception: $_" "ERROR"
    exit 1
}

Write-Log "================================================================"
Write-Log "Dispatcher finished. Full log: $LogPath"
Write-Log "================================================================"
exit $ExitCode
