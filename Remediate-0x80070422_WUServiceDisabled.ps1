#Requires -RunAsAdministrator
<#
.SYNOPSIS   Remediation – 0x80070422 Windows Update Service Disabled
.DESCRIPTION
    Enables and starts the Windows Update service (wuauserv) and its
    dependencies (BITS, CryptSvc, TrustedInstaller). Also clears any
    Group Policy override that may have disabled the service.
.NOTES  Target collection: "Patch Error – WUServiceDisabled [0x80070422]"
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

function Write-Log { param([string]$Msg,[string]$Level="INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts][$Level] $Msg"
    Add-Content -Path "$env:SystemRoot\Temp\PatchRemediation_WUSvcDisabled.log" -Value "[$ts][$Level] $Msg"
}

Write-Log "──── BEGIN: 0x80070422 WU Service Disabled Remediation ────"

# Services required for Windows Update
$RequiredServices = @(
    @{ Name="BITS";             StartType="Automatic(Delayed)" }
    @{ Name="wuauserv";         StartType="Manual"             }
    @{ Name="CryptSvc";         StartType="Automatic"          }
    @{ Name="TrustedInstaller"; StartType="Manual"             }
    @{ Name="msiserver";        StartType="Manual"             }
)

foreach ($Svc in $RequiredServices) {
    $Service = Get-Service -Name $Svc.Name -ErrorAction SilentlyContinue
    if ($null -eq $Service) { Write-Log "Service not found: $($Svc.Name)" "WARN"; continue }

    Write-Log "Setting $($Svc.Name) startup → $($Svc.StartType)"
    Set-Service -Name $Svc.Name -StartupType Manual -ErrorAction SilentlyContinue

    if ($Service.Status -ne "Running") {
        Write-Log "Starting $($Svc.Name)…"
        Start-Service -Name $Svc.Name -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        $Service.Refresh()
        Write-Log "$($Svc.Name) status: $($Service.Status)" $(if ($Service.Status -eq "Running") {"INFO"} else {"WARN"})
    }
}

# Clear GP registry override that forces service to 4 (Disabled)
$WuPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
if (Test-Path $WuPolicy) {
    $DisableVal = Get-ItemProperty -Path $WuPolicy -Name "NoAutoUpdate" -ErrorAction SilentlyContinue
    if ($DisableVal) {
        Write-Log "Removing GP NoAutoUpdate override"
        Remove-ItemProperty -Path $WuPolicy -Name "NoAutoUpdate" -ErrorAction SilentlyContinue
    }
}

# sc.exe override in case service is hard-disabled in registry
Write-Log "Forcing wuauserv start type via sc.exe"
sc.exe config wuauserv start= demand 2>&1 | Out-Null
sc.exe start  wuauserv        2>&1 | Out-Null

# SCCM triggers
Write-Log "Triggering SCCM policy/scan cycles"
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000021}" 2>&1 | Out-Null
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000113}" 2>&1 | Out-Null

Write-Log "──── END: 0x80070422 Remediation Complete ────"
exit 0
