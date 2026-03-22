#Requires -RunAsAdministrator
<#
.SYNOPSIS   Remediation – 0x80070005 Access Denied (WUA / SCCM Agent)
.DESCRIPTION
    Fixes permission issues that prevent Windows Update or the SCCM client
    from reading/writing its working directories and registry keys.
    Restarts the affected services after repair.
.NOTES  Deploy via SCCM as a script or package targeting collection:
        "Patch Error – AccessDenied [0x80070005]"
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

function Write-Log { param([string]$Msg,[string]$Level="INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts][$Level] $Msg"
    Add-Content -Path "$env:SystemRoot\Temp\PatchRemediation_AccessDenied.log" -Value "[$ts][$Level] $Msg"
}

Write-Log "──── BEGIN: 0x80070005 Access Denied Remediation ────"

# 1 – Reset ACLs on Windows Update cache directories
$Dirs = @(
    "$env:SystemRoot\SoftwareDistribution",
    "$env:SystemRoot\SoftwareDistribution\Download",
    "$env:SystemRoot\SoftwareDistribution\DataStore",
    "$env:SystemRoot\Temp",
    "$env:SystemRoot\CCM\Cache"
)
foreach ($Dir in $Dirs) {
    if (Test-Path $Dir) {
        Write-Log "Resetting ACL: $Dir"
        icacls $Dir /reset /T /Q 2>&1 | Out-Null
        icacls $Dir /grant "NT AUTHORITY\SYSTEM:(OI)(CI)F" /Q 2>&1 | Out-Null
        icacls $Dir /grant "BUILTIN\Administrators:(OI)(CI)F" /Q 2>&1 | Out-Null
        icacls $Dir /grant "NT SERVICE\wuauserv:(OI)(CI)RX" /Q 2>&1 | Out-Null
    }
}

# 2 – Restore WUA service account to LOCAL SYSTEM
Write-Log "Ensuring wuauserv runs as LocalSystem"
sc.exe config wuauserv obj= "LocalSystem" 2>&1 | Out-Null

# 3 – Reset registry permissions on WU keys
$WuKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update"
)
foreach ($Key in $WuKeys) {
    if (Test-Path $Key) {
        Write-Log "Granting SYSTEM full control on $Key"
        $Acl = Get-Acl $Key
        $Rule = New-Object System.Security.AccessControl.RegistryAccessRule(
            "NT AUTHORITY\SYSTEM","FullControl","ContainerInherit,ObjectInherit","None","Allow")
        $Acl.SetAccessRule($Rule)
        Set-Acl -Path $Key -AclObject $Acl 2>&1 | Out-Null
    }
}

# 4 – Re-register WUA DLLs
Write-Log "Re-registering core Windows Update DLLs"
$Dlls = @("wuapi.dll","wuaueng.dll","wucltui.dll","wups.dll","wups2.dll","wuweb.dll",
          "atl.dll","mssip32.dll","initpki.dll","msxml3.dll")
foreach ($Dll in $Dlls) {
    $Path = Join-Path $env:SystemRoot\System32 $Dll
    if (Test-Path $Path) { regsvr32.exe /s $Path }
}

# 5 – Restart services
Write-Log "Restarting wuauserv and ccmexec"
Restart-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Restart-Service -Name ccmexec  -Force -ErrorAction SilentlyContinue

# 6 – Trigger machine policy / scan
Write-Log "Triggering SCCM machine policy and update scan"
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000021}" 2>&1 | Out-Null
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000113}" 2>&1 | Out-Null

Write-Log "──── END: 0x80070005 Remediation Complete ────"
exit 0
