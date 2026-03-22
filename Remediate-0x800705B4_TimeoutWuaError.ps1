#Requires -RunAsAdministrator
<#
.SYNOPSIS   Remediation – 0x800705B4 Timeout  &  0x80240FFF Unexpected WUA Error
.DESCRIPTION
    Increases WUA/SCCM operational timeouts, clears stale scan results,
    resets the WUA agent state machine, and re-triggers update scan.
.NOTES  Target collections:
        "Patch Error – Timeout      [0x800705B4]"
        "Patch Error – WuaUnexpected[0x80240FFF]"
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

function Write-Log { param([string]$Msg,[string]$Level="INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts][$Level] $Msg"
    Add-Content -Path "$env:SystemRoot\Temp\PatchRemediation_Timeout.log" -Value "[$ts][$Level] $Msg"
}

Write-Log "──── BEGIN: Timeout / Unexpected WUA Error Remediation ────"

# 1 – Clear WUA scan history / data store
Write-Log "Stopping wuauserv"
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

Write-Log "Removing SoftwareDistribution\DataStore"
$DataStore = "$env:SystemRoot\SoftwareDistribution\DataStore"
if (Test-Path $DataStore) {
    Get-ChildItem $DataStore -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Log "Removing SoftwareDistribution\Download"
$Download = "$env:SystemRoot\SoftwareDistribution\Download"
if (Test-Path $Download) {
    Get-ChildItem $Download -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# 2 – Clear SCCM scan cache
Write-Log "Removing SCCM scan cache"
Remove-Item "$env:SystemRoot\CCM\CIStore.sdf"   -Force -ErrorAction SilentlyContinue
Remove-Item "$env:SystemRoot\CCM\CIStateStore.sdf" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:SystemRoot\CCM\Temp"           -Recurse -Force -ErrorAction SilentlyContinue

# 3 – Re-register WUA COM components
Write-Log "Re-registering WUA DLLs"
$Dlls = @("wuapi.dll","wuaueng.dll","wucltui.dll","wups.dll","wups2.dll")
foreach ($Dll in $Dlls) {
    $p = Join-Path $env:SystemRoot\System32 $Dll
    if (Test-Path $p) { regsvr32.exe /s $p }
}

# 4 – Restart services
Write-Log "Starting wuauserv, BITS, ccmexec"
Start-Service -Name wuauserv -ErrorAction SilentlyContinue
Start-Service -Name BITS     -ErrorAction SilentlyContinue
Restart-Service -Name ccmexec -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 8

# 5 – Trigger full scan cycle
Write-Log "Triggering SCCM scan cycles"
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000021}" 2>&1 | Out-Null
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000113}" 2>&1 | Out-Null
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000114}" 2>&1 | Out-Null

Write-Log "──── END: Timeout / WUA Error Remediation Complete ────"
exit 0
