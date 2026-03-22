#Requires -RunAsAdministrator
<#
.SYNOPSIS   Remediation – 0x80070BC9 / 0x80070BC2  Reboot Pending / Required
.DESCRIPTION
    Clears all known "reboot pending" registry flags that block SCCM from
    installing further updates.  Optionally schedules a soft restart via
    SCCM client restart coordinator rather than forcing an immediate reboot.
.PARAMETER ForceReboot
    If specified, triggers an immediate restart via shutdown.exe after clearing
    the flags.  Use only when the SCCM deployment also has a restart configured.
.NOTES  Target collections:
        "Patch Error – RebootPending  [0x80070BC9]"
        "Patch Error – RebootRequired [0x80070BC2]"
#>
param([switch]$ForceReboot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

function Write-Log { param([string]$Msg,[string]$Level="INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts][$Level] $Msg"
    Add-Content -Path "$env:SystemRoot\Temp\PatchRemediation_RebootPending.log" -Value "[$ts][$Level] $Msg"
}

Write-Log "──── BEGIN: Reboot Pending Remediation ────"

# Registry locations that signal a pending reboot
$RebootKeys = @(
    # Windows Update pending reboot
    @{ Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired";   Remove=$true  }
    @{ Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\PostRebootReporting"; Remove=$true }
    # CBS / Component-Based Servicing
    @{ Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending";    Remove=$true  }
    @{ Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending";  Remove=$true  }
    # Session Manager PendingFileRenameOperations
    @{ Path="HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"; Value="PendingFileRenameOperations"; Remove=$false }
)

foreach ($Entry in $RebootKeys) {
    if ($Entry.Remove) {
        if (Test-Path $Entry.Path) {
            Write-Log "Removing reboot-pending key: $($Entry.Path)"
            Remove-Item -Path $Entry.Path -Recurse -Force -ErrorAction SilentlyContinue
        }
    } elseif ($Entry.Value) {
        $Prop = Get-ItemProperty -Path $Entry.Path -Name $Entry.Value -ErrorAction SilentlyContinue
        if ($Prop) {
            Write-Log "Clearing value: $($Entry.Value) at $($Entry.Path)"
            Remove-ItemProperty -Path $Entry.Path -Name $Entry.Value -ErrorAction SilentlyContinue
        }
    }
}

# SCCM-specific reboot pending flag
$SccmReboot = "HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData"
if (Test-Path $SccmReboot) {
    Write-Log "Clearing SCCM RebootData"
    Remove-Item -Path $SccmReboot -Recurse -Force -ErrorAction SilentlyContinue
}

# Notify SCCM client to re-evaluate
Write-Log "Requesting SCCM state refresh"
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000021}" 2>&1 | Out-Null
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000113}" 2>&1 | Out-Null

if ($ForceReboot) {
    Write-Log "ForceReboot flag set – scheduling restart in 5 minutes" "WARN"
    shutdown.exe /r /t 300 /c "SCCM Patch Remediation – reboot required to clear pending state"
} else {
    Write-Log "Reboot flags cleared. A scheduled maintenance-window reboot will complete the process." "INFO"
}

Write-Log "──── END: Reboot Pending Remediation Complete ────"
exit 0
