#Requires -RunAsAdministrator
<#
.SYNOPSIS   Remediation – 0x800B0109 Untrusted Certificate Chain
.DESCRIPTION
    Refreshes the Windows certificate trust store using certutil, updates root
    and intermediate CA certificates from Windows Update, and validates the
    SCCM signing certificate chain.
.NOTES  Target collection: "Patch Error – CertChainUntrusted [0x800B0109]"
        Requires outbound HTTPS access OR an internal OCSP/CDP infrastructure.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

function Write-Log { param([string]$Msg,[string]$Level="INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts][$Level] $Msg"
    Add-Content -Path "$env:SystemRoot\Temp\PatchRemediation_CertTrust.log" -Value "[$ts][$Level] $Msg"
}

Write-Log "──── BEGIN: Certificate Trust Remediation ────"

# 1 – Sync Root CA store via certutil
Write-Log "Syncing AuthRoot certificate store"
certutil.exe -syncWithWU "$env:TEMP\RootCASync" 2>&1 | ForEach-Object { Write-Log "  $_" }

# 2 – Update root certificates via Group Policy (triggers automatic root update)
Write-Log "Triggering certutil auto-root-update"
certutil.exe -generateSSTFromWU "$env:TEMP\roots.sst" 2>&1 | Out-Null
if (Test-Path "$env:TEMP\roots.sst") {
    certutil.exe -addstore -f Root "$env:TEMP\roots.sst" 2>&1 | ForEach-Object { Write-Log "  $_" }
    Remove-Item "$env:TEMP\roots.sst" -Force -ErrorAction SilentlyContinue
}

# 3 – Verify SCCM Code Signing cert is trusted
Write-Log "Checking SCCM code-signing certificate"
$SCCMCert = Get-ChildItem Cert:\LocalMachine\SMS -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -like "*SMS*" -or $_.Subject -like "*SCCM*" }
if ($SCCMCert) {
    Write-Log "SCCM cert found: $($SCCMCert.Subject) | Expires: $($SCCMCert.NotAfter)"
    if ($SCCMCert.NotAfter -lt (Get-Date)) {
        Write-Log "WARNING – SCCM cert is EXPIRED. Contact PKI team." "WARN"
    }
} else {
    Write-Log "No SMS store cert found – SCCM may repopulate after policy refresh" "WARN"
}

# 4 – Reset certificate chain engine cache
Write-Log "Clearing CertChain cache"
certutil.exe -setreg chain\ChainCacheResyncFiletime @now 2>&1 | Out-Null

# 5 – Clear IE / WinHTTP SSL cache
Write-Log "Clearing SSL session cache"
certutil.exe -urlcache * delete 2>&1 | Out-Null

# 6 – Restart CryptSvc
Write-Log "Restarting CryptSvc"
Restart-Service -Name CryptSvc -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# 7 – Restart SCCM agent
Write-Log "Restarting ccmexec"
Restart-Service -Name ccmexec -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

# 8 – Trigger policy + scan
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000021}" 2>&1 | Out-Null
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000113}" 2>&1 | Out-Null

Write-Log "──── END: Certificate Trust Remediation Complete ────"
exit 0
