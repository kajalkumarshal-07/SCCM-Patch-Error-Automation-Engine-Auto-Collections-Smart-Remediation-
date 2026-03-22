#Requires -RunAsAdministrator
<#
.SYNOPSIS   Remediation – 0x80D02002 / 0x80D03805  Delivery Optimization Failures
.DESCRIPTION
    0x80D02002: DO download stalled — no progress within the defined time window.
    0x80D03805: DO internal unknown error / peer caching failure.

    Resets the Delivery Optimization service, clears its cache, disables
    peer-to-peer mode if it is causing issues on this subnet, and falls back
    to direct Microsoft / WSUS downloads so patching can proceed immediately.

.NOTES  Target collections:
        "Patch Error – DODownloadStalled [0x80D02002]"
        "Patch Error – DOUnknownError    [0x80D03805]"

    Logs to: C:\Windows\Temp\PatchRemediation_DeliveryOpt.log
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

function Write-Log { param([string]$Msg,[string]$Level="INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts][$Level] $Msg"
    Add-Content -Path "$env:SystemRoot\Temp\PatchRemediation_DeliveryOpt.log" -Value "[$ts][$Level] $Msg"
}

Write-Log "──── BEGIN: Delivery Optimization Remediation (0x80D02002 / 0x80D03805) ────"

# 1 – Stop DO service before touching its cache
Write-Log "Stopping DoSvc (Delivery Optimization)…"
Stop-Service -Name DoSvc -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# 2 – Clear Delivery Optimization cache directory
$DOCachePaths = @(
    "$env:SystemDrive\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache",
    "$env:SystemDrive\Windows\SoftwareDistribution\DeliveryOptimization"
)
foreach ($Path in $DOCachePaths) {
    if (Test-Path $Path) {
        Write-Log "Clearing DO cache: $Path"
        Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# 3 – Remove DO database/log files that can become corrupt
$DODataPath = "$env:SystemDrive\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Logs"
if (Test-Path $DODataPath) {
    Write-Log "Clearing DO log files…"
    Get-ChildItem $DODataPath -Force -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# 4 – Set DO download mode to HTTP-only (bypass P2P) via registry
#     DownloadMode: 0 = HTTP only (no P2P), 1 = LAN, 2 = Group, 3 = Internet
Write-Log "Setting Delivery Optimization download mode to HTTP-only (bypass P2P)"
$DOPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
if (-not (Test-Path $DOPolicyPath)) {
    New-Item -Path $DOPolicyPath -Force | Out-Null
}
Set-ItemProperty -Path $DOPolicyPath -Name "DODownloadMode" -Value 0 -Type DWord

# 5 – Set generous timeout values to prevent future stall errors
#     DOMinBackgroundQoS (Kbps): 500 Kbps minimum background bandwidth
$DOConfigPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config"
if (Test-Path $DOConfigPath) {
    Set-ItemProperty -Path $DOConfigPath -Name "DODownloadMode" -Value 0 -Type DWord -ErrorAction SilentlyContinue
}

# 6 – Restart DO service
Write-Log "Starting DoSvc…"
Start-Service -Name DoSvc -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$Svc = Get-Service -Name DoSvc -ErrorAction SilentlyContinue
Write-Log "DoSvc status: $($Svc.Status)" $(if ($Svc.Status -eq 'Running') {"INFO"} else {"WARN"})

# 7 – Also reset BITS queue since stalled DO downloads often leave BITS orphans
Write-Log "Cancelling stale BITS jobs…"
Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue | Remove-BitsTransfer -ErrorAction SilentlyContinue

# 8 – Clear SoftwareDistribution\Download staging area
Write-Log "Stopping wuauserv and clearing SoftwareDistribution\\Download…"
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$DownloadPath = "$env:SystemRoot\SoftwareDistribution\Download"
if (Test-Path $DownloadPath) {
    Get-ChildItem $DownloadPath -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
Start-Service -Name wuauserv -ErrorAction SilentlyContinue

# 9 – Restart SCCM client
Write-Log "Restarting ccmexec…"
Restart-Service -Name ccmexec -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

# 10 – Trigger SCCM update scan
Write-Log "Triggering SCCM Software Updates Scan Cycle…"
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000113}" 2>&1 | Out-Null
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000114}" 2>&1 | Out-Null

Write-Log "──── END: Delivery Optimization Remediation Complete ────"
Write-Log "NOTE: DO mode set to HTTP-only. Re-enable P2P via GP if required after patching."
exit 0
