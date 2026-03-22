#Requires -RunAsAdministrator
<#
.SYNOPSIS   Remediation – 0x800705B9  Windows Unable to Parse Requested XML Data
.DESCRIPTION
    Windows Update or SCCM received a malformed / incomplete XML response from
    the WSUS server or Windows Update service endpoint. Common causes:
      - Corrupt DataStore.edb (WU local database)
      - Truncated or malformed scan response cached on disk
      - WSUS IIS application pool memory issues delivering corrupt XML
      - Proxy stripping or modifying HTTP responses mid-stream

    This script clears the WU local database and scan cache, resets the
    WUA XML-handling COM components, and forces a clean scan.

.NOTES  Target collection: "Patch Error – XmlParseError [0x800705B9]"
        Logs to: C:\Windows\Temp\PatchRemediation_XmlParse.log
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

function Write-Log { param([string]$Msg,[string]$Level="INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts][$Level] $Msg"
    Add-Content -Path "$env:SystemRoot\Temp\PatchRemediation_XmlParse.log" -Value "[$ts][$Level] $Msg"
}

Write-Log "──── BEGIN: 0x800705B9 XML Parse Error Remediation ────"

# 1 – Stop Windows Update service
Write-Log "Stopping wuauserv and BITS…"
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Stop-Service -Name BITS     -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# 2 – Delete the Windows Update local database (DataStore.edb)
#     This is the primary fix — DataStore.edb holds cached scan XML;
#     if corrupt it causes repeated 0x800705B9 on every scan attempt
$DataStorePaths = @(
    "$env:SystemRoot\SoftwareDistribution\DataStore\DataStore.edb",
    "$env:SystemRoot\SoftwareDistribution\DataStore\Logs"
)
foreach ($P in $DataStorePaths) {
    if (Test-Path $P) {
        Write-Log "Removing corrupt data store: $P"
        Remove-Item $P -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Removed: $P"
    }
}

# 3 – Clear entire SoftwareDistribution scan cache
Write-Log "Clearing SoftwareDistribution\\DataStore…"
$DataStoreDir = "$env:SystemRoot\SoftwareDistribution\DataStore"
if (Test-Path $DataStoreDir) {
    Get-ChildItem $DataStoreDir -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Log "Clearing SoftwareDistribution\\Download…"
$DownloadDir = "$env:SystemRoot\SoftwareDistribution\Download"
if (Test-Path $DownloadDir) {
    Get-ChildItem $DownloadDir -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# 4 – Re-register XML and WUA COM components
Write-Log "Re-registering XML and WUA COM components…"
$XmlDlls = @("msxml3.dll","msxml6.dll")
foreach ($Dll in $XmlDlls) {
    $Path = Join-Path $env:SystemRoot\System32 $Dll
    if (Test-Path $Path) {
        Write-Log "  regsvr32 /s $Dll"
        regsvr32.exe /s $Path
    }
}

$WuaDlls = @("wuapi.dll","wuaueng.dll","wucltui.dll","wups.dll","wups2.dll","wuweb.dll")
foreach ($Dll in $WuaDlls) {
    $Path = Join-Path $env:SystemRoot\System32 $Dll
    if (Test-Path $Path) { regsvr32.exe /s $Path }
}

# 5 – Reset WinHTTP proxy (in case proxy is mangling XML responses)
Write-Log "Resetting WinHTTP proxy…"
netsh winhttp reset proxy 2>&1 | Out-Null

# 6 – Flush DNS (stale WSUS DNS can cause partial responses)
Write-Log "Flushing DNS cache…"
ipconfig /flushdns 2>&1 | Out-Null

# 7 – Restart services
Write-Log "Restarting wuauserv, BITS, ccmexec…"
Start-Service -Name BITS     -ErrorAction SilentlyContinue
Start-Service -Name wuauserv -ErrorAction SilentlyContinue
Restart-Service -Name ccmexec -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 6

# 8 – Trigger clean scan
Write-Log "Triggering SCCM policy and Software Updates Scan…"
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000021}" 2>&1 | Out-Null
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000113}" 2>&1 | Out-Null

Write-Log "──── END: 0x800705B9 XML Parse Remediation Complete ────"
exit 0
