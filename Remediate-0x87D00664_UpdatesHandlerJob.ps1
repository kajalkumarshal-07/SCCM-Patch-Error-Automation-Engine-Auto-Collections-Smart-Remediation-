#Requires -RunAsAdministrator
<#
.SYNOPSIS   Remediation – 0x87D00664 / 0x87D00665  SCCM Updates Handler Job Errors
.DESCRIPTION
    0x87D00664: "Updates handler job was cancelled" — The SCCM Software Updates
                handler job was unexpectedly cancelled. Often caused by a stale
                WUAHandler state, CCM policy conflict, or interrupted scan cycle.

    0x87D00665: "No updates to process in the job" — The handler job found
                nothing to action, indicating a policy/scan sync gap between
                the SCCM server and client.

    Both errors require resetting the SCCM client update agent state and
    forcing a fresh policy + scan cycle.

.NOTES  Target collections:
        "Patch Error – UpdatesHandlerCancelled [0x87D00664]"
        "Patch Error – NoUpdatesInJob          [0x87D00665]"
        Logs to: C:\Windows\Temp\PatchRemediation_HandlerJob.log
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

function Write-Log { param([string]$Msg,[string]$Level="INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts][$Level] $Msg"
    Add-Content -Path "$env:SystemRoot\Temp\PatchRemediation_HandlerJob.log" -Value "[$ts][$Level] $Msg"
}

Write-Log "──── BEGIN: 0x87D00664 / 0x87D00665 Updates Handler Remediation ────"

# 1 – Stop SCCM client
Write-Log "Stopping ccmexec…"
Stop-Service -Name ccmexec -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 4

# 2 – Clear SCCM Software Updates state store files
#     These files hold the current handler job state; stale entries cause cancellations
$StateFiles = @(
    "$env:SystemRoot\CCM\StateMessageStore",
    "$env:SystemRoot\CCM\SoftwareDistribution",
    "$env:SystemRoot\CCM\Temp"
)
foreach ($P in $StateFiles) {
    if (Test-Path $P) {
        Write-Log "Clearing SCCM state path: $P"
        Get-ChildItem $P -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# 3 – Remove stale WUAHandler action history
$WUAHandlerDB = @(
    "$env:SystemRoot\CCM\WUAHandler.log",
    "$env:SystemRoot\CCM\UpdatesDeployment.log"
)
foreach ($F in $WUAHandlerDB) {
    if (Test-Path $F) {
        Write-Log "Archiving stale log: $F"
        Rename-Item $F ($F + ".bak") -ErrorAction SilentlyContinue
    }
}

# 4 – Remove stale CIStore (compliance/policy database) so it rebuilds cleanly
$CIStoreFiles = @(
    "$env:SystemRoot\CCM\CIStore.sdf",
    "$env:SystemRoot\CCM\CIStateStore.sdf",
    "$env:SystemRoot\CCM\CITaskStore.sdf"
)
foreach ($F in $CIStoreFiles) {
    if (Test-Path $F) {
        Write-Log "Removing CI store: $F"
        Remove-Item $F -Force -ErrorAction SilentlyContinue
    }
}

# 5 – Restart SCCM client — it will rebuild CI stores on startup
Write-Log "Starting ccmexec (CI stores will rebuild)…"
Start-Service -Name ccmexec -ErrorAction SilentlyContinue
Start-Sleep -Seconds 10  # Allow agent to fully initialise before triggering cycles

# 6 – Trigger Machine Policy to fetch latest deployment assignments
Write-Log "Triggering Machine Policy Retrieval…"
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000021}" 2>&1 | Out-Null
Start-Sleep -Seconds 5

# 7 – Trigger Policy Evaluation
Write-Log "Triggering Machine Policy Evaluation…"
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000022}" 2>&1 | Out-Null
Start-Sleep -Seconds 5

# 8 – Trigger Software Updates Scan and Deployment Evaluation
Write-Log "Triggering Software Updates Scan Cycle…"
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000113}" 2>&1 | Out-Null
Start-Sleep -Seconds 3

Write-Log "Triggering Software Updates Deployment Evaluation Cycle…"
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000114}" 2>&1 | Out-Null

Write-Log "──── END: Updates Handler Remediation Complete ────"
Write-Log "Monitor UpdatesDeployment.log and WUAHandler.log for handler job status."
exit 0
