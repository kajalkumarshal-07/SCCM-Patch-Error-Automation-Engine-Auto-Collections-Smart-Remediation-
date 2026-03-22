#Requires -RunAsAdministrator
<#
.SYNOPSIS   Remediation – 0x8024402C / 0x80244022  WSUS / SUP Connection Failure
.DESCRIPTION
    Resolves connectivity failures to the SCCM Software Update Point (WSUS).
    Covers proxy misconfiguration, stale WUA registry settings, and
    WinHTTP proxy issues.
.NOTES  Target collections:
        "Patch Error – WsusConnectFail [0x8024402C]"
        "Patch Error – WsusNoService   [0x80244022]"
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

function Write-Log { param([string]$Msg,[string]$Level="INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts][$Level] $Msg"
    Add-Content -Path "$env:SystemRoot\Temp\PatchRemediation_WSUSConnect.log" -Value "[$ts][$Level] $Msg"
}

Write-Log "──── BEGIN: WSUS Connectivity Remediation ────"

# 1 – Clear stale WUA server registry keys so SCCM policy repopulates them
$WuKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate"
)
$StaleValues = @("WUServer","WUStatusServer","SusClientId","SusClientIDValidation","AccountDomainSid","PingID","OldTargetGroup")
foreach ($Key in $WuKeys) {
    foreach ($Val in $StaleValues) {
        if (Get-ItemProperty -Path $Key -Name $Val -ErrorAction SilentlyContinue) {
            Write-Log "Removing stale WU reg value: $Val"
            Remove-ItemProperty -Path $Key -Name $Val -ErrorAction SilentlyContinue
        }
    }
}

# 2 – Reset WinHTTP proxy to direct (inherit from IE/WinINET automatically)
Write-Log "Resetting WinHTTP proxy"
netsh winhttp reset proxy 2>&1 | Out-Null

# 3 – If a system-wide proxy is set, import it into WinHTTP
Write-Log "Attempting to import IE proxy into WinHTTP"
netsh winhttp import proxy source=ie 2>&1 | Out-Null

# 4 – Clear Software Distribution temp data
$SDPaths = @(
    "$env:SystemRoot\SoftwareDistribution\ScanFile",
    "$env:SystemRoot\SoftwareDistribution\ReportingEvents.log"
)
foreach ($P in $SDPaths) {
    if (Test-Path $P) {
        Write-Log "Removing: $P"
        Remove-Item -Path $P -Force -Recurse -ErrorAction SilentlyContinue
    }
}

# 5 – Flush DNS and reset Winsock (connectivity stabiliser)
Write-Log "Flushing DNS resolver cache"
ipconfig /flushdns 2>&1 | Out-Null
Write-Log "Resetting Winsock"
netsh winsock reset catalog 2>&1 | Out-Null

# 6 – Restart WUA
Write-Log "Restarting wuauserv"
Stop-Service  -Name wuauserv -Force  -ErrorAction SilentlyContinue
Start-Sleep   -Seconds 2
Start-Service -Name wuauserv         -ErrorAction SilentlyContinue

# 7 – Restart CCM agent so it re-reads the SUP from policy
Write-Log "Restarting SCCM client agent (ccmexec)"
Restart-Service -Name ccmexec -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

# 8 – Trigger SCCM policy + update scan
Write-Log "Triggering SCCM cycles"
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000021}" 2>&1 | Out-Null
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000113}" 2>&1 | Out-Null

Write-Log "──── END: WSUS Connectivity Remediation Complete ────"
exit 0
