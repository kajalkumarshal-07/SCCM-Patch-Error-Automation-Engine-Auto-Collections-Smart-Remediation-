#Requires -RunAsAdministrator
<#
.SYNOPSIS   Remediation – 0x8007139F  Group or Resource Not in Correct State
.DESCRIPTION
    0x8007139F (ERROR_INVALID_STATE) in a patching context means a Windows
    Update resource, service group, or internal state machine component is in
    an invalid/inconsistent state.

    Common triggers in SCCM environments:
      - Windows Update internal job queue stuck in a non-idle state
      - WUA scan already running when SCCM triggered another scan (race condition)
      - Windows Installer transaction log in an incomplete/rolled-back state
      - Service Control Manager reporting a service group conflict

    This script kills stale WUA/CCM scan jobs, resets the service group
    dependencies, clears the WUA job queue, and restarts the update stack cleanly.

.NOTES  Target collection: "Patch Error – InvalidResourceState [0x8007139F]"
        Logs to: C:\Windows\Temp\PatchRemediation_0x8007139F.log
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

function Write-Log { param([string]$Msg,[string]$Level="INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts][$Level] $Msg"
    Add-Content -Path "$env:SystemRoot\Temp\PatchRemediation_0x8007139F.log" -Value "[$ts][$Level] $Msg"
}

Write-Log "──── BEGIN: 0x8007139F Invalid State Remediation ────"

# 1 – Kill any orphaned WUA/SCCM scan processes
Write-Log "Terminating any hung WUAHandler or CcmExec scan threads…"
$HungProcs = @("wuauclt","TrustedInstaller","msiexec")
foreach ($P in $HungProcs) {
    $Running = Get-Process -Name $P -ErrorAction SilentlyContinue
    if ($Running) {
        Write-Log "  Stopping process: $P (PID $($Running.Id))" "WARN"
        Stop-Process -Name $P -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }
}

# 2 – Full service group stop in dependency order
Write-Log "Stopping update service group in order…"
$StopOrder = @("ccmexec","wuauserv","BITS","TrustedInstaller","msiserver","CryptSvc")
foreach ($Svc in $StopOrder) {
    $S = Get-Service -Name $Svc -ErrorAction SilentlyContinue
    if ($S -and $S.Status -ne "Stopped") {
        Write-Log "  Stopping: $Svc"
        Stop-Service -Name $Svc -Force -ErrorAction SilentlyContinue
    }
}
Start-Sleep -Seconds 4

# 3 – Clear WUA internal state
Write-Log "Clearing WUA DataStore and Download staging…"
$ClearPaths = @(
    "$env:SystemRoot\SoftwareDistribution\DataStore",
    "$env:SystemRoot\SoftwareDistribution\Download",
    "$env:SystemRoot\Temp\CBS"
)
foreach ($P in $ClearPaths) {
    if (Test-Path $P) {
        Get-ChildItem $P -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "  Cleared: $P"
    }
}

# 4 – Remove Windows Installer transaction logs that may show incomplete state
$MsiLogs = Get-ChildItem "$env:SystemRoot\Temp" -Filter "MSI*.tmp" -ErrorAction SilentlyContinue
foreach ($F in $MsiLogs) {
    Write-Log "  Removing MSI temp: $($F.Name)"
    Remove-Item $F.FullName -Force -ErrorAction SilentlyContinue
}

# 5 – Reset service start types to expected values
Write-Log "Resetting service start types…"
sc.exe config CryptSvc        start= auto   2>&1 | Out-Null
sc.exe config BITS            start= delayed-auto 2>&1 | Out-Null
sc.exe config wuauserv        start= demand 2>&1 | Out-Null
sc.exe config TrustedInstaller start= demand 2>&1 | Out-Null
sc.exe config msiserver       start= demand 2>&1 | Out-Null

# 6 – Start services in dependency order
Write-Log "Starting services in dependency order…"
$StartOrder = @("CryptSvc","BITS","msiserver","TrustedInstaller","wuauserv")
foreach ($Svc in $StartOrder) {
    Start-Service -Name $Svc -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 300
}

# 7 – Restart SCCM client
Write-Log "Starting ccmexec…"
Start-Service -Name ccmexec -ErrorAction SilentlyContinue
Start-Sleep -Seconds 8

# 8 – Trigger full policy + scan cycle
Write-Log "Triggering SCCM Machine Policy and Software Updates Scan…"
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000021}" 2>&1 | Out-Null
Start-Sleep -Seconds 3
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000113}" 2>&1 | Out-Null

Write-Log "──── END: 0x8007139F Remediation Complete ────"
exit 0
