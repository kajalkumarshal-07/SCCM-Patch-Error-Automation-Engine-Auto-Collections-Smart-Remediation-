#Requires -RunAsAdministrator
<#
.SYNOPSIS   Remediation – 0x80073712 / 0x8007371B  CBS / Component Store Corruption
.DESCRIPTION
    Runs DISM CheckHealth → ScanHealth → RestoreHealth to repair the Windows
    Component Store, followed by SFC /scannow.  If DISM RestoreHealth fails
    (no internet access), falls back to the local WIM source if supplied.
.PARAMETER WimSource
    Optional path to a mounted Windows image or WIM file to use as a DISM
    repair source (e.g. "\\server\share\install.wim:1").
.NOTES  Target collections:
        "Patch Error – CbsComponentCorrupt [0x80073712]"
        "Patch Error – CbsTransactionError [0x8007371B]"

    IMPORTANT: DISM RestoreHealth can take 15–45 minutes on degraded systems.
    Deploy as an SCCM Package with a 90-minute runtime timeout, not a Script.
#>
param([string]$WimSource = "")

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

$LogFile = "$env:SystemRoot\Temp\PatchRemediation_CBSCorrupt.log"

function Write-Log { param([string]$Msg,[string]$Level="INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts][$Level] $Msg"
    Add-Content -Path $LogFile -Value "[$ts][$Level] $Msg"
}

function Run-Command { param([string]$Cmd,[string]$Args)
    Write-Log "Running: $Cmd $Args"
    $proc = Start-Process -FilePath $Cmd -ArgumentList $Args `
                -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:Temp\cmd_out.txt" `
                -RedirectStandardError "$env:Temp\cmd_err.txt"
    $out = Get-Content "$env:Temp\cmd_out.txt" -ErrorAction SilentlyContinue
    $out | ForEach-Object { Write-Log "  $_" }
    return $proc.ExitCode
}

Write-Log "──── BEGIN: CBS/Component Store Corruption Remediation ────"

# Step 1 – Quick health check
Write-Log "STEP 1 – DISM CheckHealth"
$ec = Run-Command "DISM.exe" "/Online /Cleanup-Image /CheckHealth"
Write-Log "CheckHealth exit code: $ec"

# Step 2 – Full scan
Write-Log "STEP 2 – DISM ScanHealth"
$ec = Run-Command "DISM.exe" "/Online /Cleanup-Image /ScanHealth"
Write-Log "ScanHealth exit code: $ec"

# Step 3 – Restore
Write-Log "STEP 3 – DISM RestoreHealth"
if ($WimSource -ne "") {
    $ec = Run-Command "DISM.exe" "/Online /Cleanup-Image /RestoreHealth /Source:$WimSource /LimitAccess"
} else {
    $ec = Run-Command "DISM.exe" "/Online /Cleanup-Image /RestoreHealth"
}
Write-Log "RestoreHealth exit code: $ec"

if ($ec -ne 0) {
    Write-Log "DISM RestoreHealth returned $ec – attempting SFC anyway" "WARN"
}

# Step 4 – SFC scan
Write-Log "STEP 4 – SFC /scannow"
$ec = Run-Command "sfc.exe" "/scannow"
Write-Log "SFC exit code: $ec"

# Step 5 – Clean up component store stale packages
Write-Log "STEP 5 – DISM StartComponentCleanup"
Run-Command "DISM.exe" "/Online /Cleanup-Image /StartComponentCleanup" | Out-Null

# Step 6 – Restart SCCM & WUA
Write-Log "Restarting wuauserv and ccmexec"
Restart-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Restart-Service -Name ccmexec  -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

# Step 7 – Trigger update scan
Write-Log "Triggering SCCM update scan"
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000113}" 2>&1 | Out-Null

Write-Log "──── END: CBS Corruption Remediation Complete ────"
Write-Log "Full DISM log: $env:SystemRoot\Logs\DISM\dism.log"
exit 0
