#Requires -Version 5.1
<#
.SYNOPSIS
    Creates SCCM Device Collections for each known Windows Update / SCCM patching error code.

.DESCRIPTION
    Connects to the SCCM Site Server and creates one Device Collection per error code,
    each with a WQL membership rule querying SMS_G_System_WORKSTATION_STATUS.LastErrorCode.
    Collections are grouped under a single console folder for easy management.

    Covers 29 error codes including:
      - Core WUA / Windows Update errors
      - SCCM client handler job errors (0x87D00664, 0x87D00665)
      - Delivery Optimization errors  (0x80D02002, 0x80D03805)
      - CBS / Component Store corruption
      - Reboot state errors
      - Download / DP / BITS failures
      - MSI / file lock errors
      - Certificate trust errors
      - XML parse / DataStore corruption (0x800705B9)
      - CRC data errors / shutdown-interrupted installs (0x80070017, 0x8007045B)
      - Invalid resource state (0x8007139F)

.PARAMETER SiteServer
    FQDN or NetBIOS name of the SCCM Primary Site Server.

.PARAMETER SiteCode
    Three-character SCCM Site Code (e.g. "PS1").

.PARAMETER ParentFolderName
    Console subfolder under Device Collections. Created if it does not exist.
    Default: "Patch Error Collections"

.PARAMETER LimitingCollectionName
    Limiting collection for all new collections.
    Default: "All Systems"

.PARAMETER RefreshIntervalHours
    Membership refresh interval in hours. Default: 4

.PARAMETER WhatIf
    Dry-run mode - shows what would be created without touching SCCM.

.EXAMPLE
    .\SCCM_Create-PatchErrorCollections.ps1 -SiteServer "SCCMSERVER.domain.local" -SiteCode "PS1"

.EXAMPLE
    .\SCCM_Create-PatchErrorCollections.ps1 -SiteServer "SCCM01" -SiteCode "PS1" -WhatIf

.EXAMPLE
    .\SCCM_Create-PatchErrorCollections.ps1 `
        -SiteServer             "SCCMSERVER.domain.local" `
        -SiteCode               "PS1" `
        -ParentFolderName       "Patch Errors" `
        -LimitingCollectionName "All Workstations" `
        -RefreshIntervalHours   6

.NOTES
    Author   : IT Engineering
    Version  : 2.0
    Requires : ConfigurationManager PowerShell module (SCCM Admin Console installed)
    Run As   : Account with SCCM Full Administrator or Collections RBAC role
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$SiteServer,

    [Parameter(Mandatory)]
    [string]$SiteCode,

    [string]$ParentFolderName       = "Patch Error Collections",
    [string]$LimitingCollectionName = "All Systems",
    [int]   $RefreshIntervalHours   = 4
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =============================================================================
# ERROR CODE CATALOGUE  -  29 entries
#
# DecimalCode = [uint32] equivalent of the hex code, used in WQL
# WQL syntax:  SMS_G_System_WORKSTATION_STATUS.LastErrorCode = <DecimalCode>
# =============================================================================
$PatchErrors = @(

    # -------------------------------------------------------------------------
    # Core Windows / WUA errors
    # -------------------------------------------------------------------------
    @{
        Code              = "0x80070005"
        ShortName         = "AccessDenied"
        Description       = "Access Denied - WUA or SCCM agent lacks permission to directories or registry"
        DecimalCode       = 2147942405
        RemediationScript = "Remediate-0x80070005_AccessDenied.ps1"
    },
    @{
        Code              = "0x80070002"
        ShortName         = "FileNotFound"
        Description       = "Source file not found - content missing from DP cache or local staging area"
        DecimalCode       = 2147942402
        RemediationScript = "Remediate-0x80070002_DownloadFailed.ps1"
    },
    @{
        Code              = "0x8007000E"
        ShortName         = "OutOfMemory"
        Description       = "Insufficient memory during update processing - staging cleanup required"
        DecimalCode       = 2147942414
        RemediationScript = "Remediate-0x800705B4_TimeoutWuaError.ps1"
    },
    @{
        Code              = "0x80070017"
        ShortName         = "CRCDataError"
        Description       = "Cyclic Redundancy Check failure - corrupt cached download on disk"
        DecimalCode       = 2147942423
        RemediationScript = "Remediate-0x80070017_CRC_Shutdown.ps1"
    },
    @{
        Code              = "0x80070020"
        ShortName         = "FileLocked"
        Description       = "File locked by another process - update install blocked"
        DecimalCode       = 2147942432
        RemediationScript = "Remediate-0x80070643_MsiFileLocked.ps1"
    },
    @{
        Code              = "0x80070422"
        ShortName         = "WUServiceDisabled"
        Description       = "Windows Update service is disabled or startup type prevents it from running"
        DecimalCode       = 2147943458
        RemediationScript = "Remediate-0x80070422_WUServiceDisabled.ps1"
    },
    @{
        Code              = "0x8007045B"
        ShortName         = "ShutdownInProgress"
        Description       = "System shutdown was in progress during install - partial install state left behind"
        DecimalCode       = 2147943515
        RemediationScript = "Remediate-0x80070017_CRC_Shutdown.ps1"
    },
    @{
        Code              = "0x800705B4"
        ShortName         = "Timeout"
        Description       = "Operation timed out during download or install"
        DecimalCode       = 2147943860
        RemediationScript = "Remediate-0x800705B4_TimeoutWuaError.ps1"
    },
    @{
        Code              = "0x800705B9"
        ShortName         = "XmlParseError"
        Description       = "Windows unable to parse XML data - corrupt DataStore.edb or malformed WSUS response"
        DecimalCode       = 2147944889
        RemediationScript = "Remediate-0x800705B9_XmlParseError.ps1"
    },
    @{
        Code              = "0x80070BC2"
        ShortName         = "RebootRequired"
        Description       = "Update installed - device reboot required to finalise"
        DecimalCode       = 2147944386
        RemediationScript = "Remediate-0x80070BC9_RebootPending.ps1"
    },
    @{
        Code              = "0x80070BC9"
        ShortName         = "RebootPending"
        Description       = "Pending reboot is blocking further update installation"
        DecimalCode       = 2147944393
        RemediationScript = "Remediate-0x80070BC9_RebootPending.ps1"
    },
    @{
        Code              = "0x80070643"
        ShortName         = "MsiInstallFailed"
        Description       = "Fatal MSI/installer error - orphaned temp files or corrupt installer state"
        DecimalCode       = 2147943987
        RemediationScript = "Remediate-0x80070643_MsiFileLocked.ps1"
    },
    @{
        Code              = "0x8007139F"
        ShortName         = "InvalidResourceState"
        Description       = "Group or resource not in correct state - WUA scan race condition or SCM conflict"
        DecimalCode       = 2147946399
        RemediationScript = "Remediate-0x8007139F_InvalidState.ps1"
    },

    # -------------------------------------------------------------------------
    # CBS / Component Store
    # -------------------------------------------------------------------------
    @{
        Code              = "0x80073712"
        ShortName         = "CbsComponentCorrupt"
        Description       = "Windows Component Store / CBS corruption detected - DISM repair required"
        DecimalCode       = 2147954450
        RemediationScript = "Remediate-0x80073712_CBSCorrupt.ps1"
    },
    @{
        Code              = "0x8007371B"
        ShortName         = "CbsTransactionError"
        Description       = "CBS transaction/manifest error during update apply"
        DecimalCode       = 2147954459
        RemediationScript = "Remediate-0x80073712_CBSCorrupt.ps1"
    },

    # -------------------------------------------------------------------------
    # WUA agent internal errors
    # -------------------------------------------------------------------------
    @{
        Code              = "0x80240010"
        ShortName         = "WuaCancelled"
        Description       = "Update cancelled by user or Group Policy during download or install"
        DecimalCode       = 2145120272
        RemediationScript = "Remediate-0x800705B4_TimeoutWuaError.ps1"
    },
    @{
        Code              = "0x80240022"
        ShortName         = "AllUpdatesNotApplicable"
        Description       = "All updates returned as not applicable - scan cache or policy mismatch"
        DecimalCode       = 2145116194
        RemediationScript = "Remediate-0x800705B4_TimeoutWuaError.ps1"
    },
    @{
        Code              = "0x80240FFF"
        ShortName         = "WuaUnexpectedError"
        Description       = "Unexpected WUA agent error - DataStore or agent component corruption"
        DecimalCode       = 2145120255
        RemediationScript = "Remediate-0x800705B4_TimeoutWuaError.ps1"
    },
    @{
        Code              = "0x800F0991"
        ShortName         = "SFXExtractionError"
        Description       = "Unknown Error (-2146498159) - SFX/cab extraction failure or CBS manifest mismatch"
        DecimalCode       = 2148533137
        RemediationScript = "Remediate-0x800F0991_UnknownSFXError.ps1"
    },

    # -------------------------------------------------------------------------
    # WSUS / Software Update Point connectivity
    # -------------------------------------------------------------------------
    @{
        Code              = "0x80244022"
        ShortName         = "WsusNoService"
        Description       = "WSUS server returned HTTP 503 Service Unavailable"
        DecimalCode       = 2149843490
        RemediationScript = "Remediate-0x8024402C_WsusConnectFail.ps1"
    },
    @{
        Code              = "0x8024402C"
        ShortName         = "WsusConnectFail"
        Description       = "Cannot connect to WSUS/SUP - proxy misconfiguration or DNS failure"
        DecimalCode       = 2149843500
        RemediationScript = "Remediate-0x8024402C_WsusConnectFail.ps1"
    },
    @{
        Code              = "0xC1800118"
        ShortName         = "WsusDeclined"
        Description       = "Update declined on WSUS server - approval or policy issue"
        DecimalCode       = 3247411992
        RemediationScript = "Remediate-0x8024402C_WsusConnectFail.ps1"
    },

    # -------------------------------------------------------------------------
    # Download / BITS / Distribution Point
    # -------------------------------------------------------------------------
    @{
        Code              = "0x80246007"
        ShortName         = "DownloadFailed"
        Description       = "Content download failed - Distribution Point unavailable or BITS error"
        DecimalCode       = 2149844999
        RemediationScript = "Remediate-0x80070002_DownloadFailed.ps1"
    },

    # -------------------------------------------------------------------------
    # Delivery Optimization  (from IT Engineering live environment)
    # -------------------------------------------------------------------------
    @{
        Code              = "0x80D02002"
        ShortName         = "DODownloadStalled"
        Description       = "Delivery Optimization download stalled - no progress within defined time window"
        DecimalCode       = 2160919554
        RemediationScript = "Remediate-0x80D02002_DeliveryOptimization.ps1"
    },
    @{
        Code              = "0x80D03805"
        ShortName         = "DOUnknownError"
        Description       = "Delivery Optimization internal unknown error - peer caching or DO service failure"
        DecimalCode       = 2160920581
        RemediationScript = "Remediate-0x80D02002_DeliveryOptimization.ps1"
    },

    # -------------------------------------------------------------------------
    # Certificate / PKI
    # -------------------------------------------------------------------------
    @{
        Code              = "0x800B0109"
        ShortName         = "CertChainUntrusted"
        Description       = "Certificate chain issued by untrusted authority - Root CA store needs update"
        DecimalCode       = 2148204809
        RemediationScript = "Remediate-0x800B0109_CertChainUntrusted.ps1"
    },

    # -------------------------------------------------------------------------
    # SCCM client / handler job errors  (from IT Engineering live environment)
    # -------------------------------------------------------------------------
    @{
        Code              = "0x87D00324"
        ShortName         = "AppNotDetected"
        Description       = "Application not detected after installation - SCCM detection rule mismatch"
        DecimalCode       = 2278556452
        RemediationScript = "Remediate-0x80070422_WUServiceDisabled.ps1"
    },
    @{
        Code              = "0x87D00664"
        ShortName         = "UpdatesHandlerCancelled"
        Description       = "SCCM updates handler job was cancelled - stale WUAHandler state or CCM policy conflict"
        DecimalCode       = 2278620772
        RemediationScript = "Remediate-0x87D00664_UpdatesHandlerJob.ps1"
    },
    @{
        Code              = "0x87D00665"
        ShortName         = "NoUpdatesInJob"
        Description       = "No updates to process in SCCM handler job - policy/scan sync gap between server and client"
        DecimalCode       = 2278620773
        RemediationScript = "Remediate-0x87D00664_UpdatesHandlerJob.ps1"
    }
)

# =============================================================================
# Helpers
# =============================================================================
function Write-Banner {
    param([string]$Text, [string]$Color = "Cyan")
    $bar = "-" * ($Text.Length + 4)
    Write-Host ""
    Write-Host "  $bar"  -ForegroundColor $Color
    Write-Host "  | $Text |" -ForegroundColor $Color
    Write-Host "  $bar"  -ForegroundColor $Color
    Write-Host ""
}
function Write-Step {
    param([string]$Icon, [string]$Text, [string]$Color = "White")
    Write-Host "  $Icon  $Text" -ForegroundColor $Color
}

# =============================================================================
# Load ConfigMgr module and connect to site
# =============================================================================
Write-Banner "SCCM Patch Error Collection Creator  v2.0"

Write-Step ">" "Loading ConfigurationManager module..."
if (-not (Get-Module ConfigurationManager -ListAvailable)) {
    Write-Error "ConfigurationManager module not found. Install the SCCM Admin Console on this machine."
}
Import-Module ConfigurationManager -ErrorAction Stop

$SiteDrive = "${SiteCode}:"
if (-not (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) {
    Write-Step ">" "Creating CMSite PSDrive for site $SiteCode on $SiteServer..."
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SiteServer -ErrorAction Stop | Out-Null
}
Set-Location $SiteDrive

# =============================================================================
# Ensure parent console folder exists
# =============================================================================
Write-Step ">" "Checking console folder: '$ParentFolderName'..."
$FolderPath = "${SiteDrive}\DeviceCollection\$ParentFolderName"

if (-not (Test-Path $FolderPath)) {
    Write-Step "+" "Creating console folder: $ParentFolderName" "Yellow"
    if ($PSCmdlet.ShouldProcess("DeviceCollection", "Create folder '$ParentFolderName'")) {
        New-Item -Path "${SiteDrive}\DeviceCollection" -Name $ParentFolderName -ItemType Directory | Out-Null
    }
}

# =============================================================================
# Refresh schedule
# =============================================================================
$Schedule = New-CMSchedule -RecurInterval Hours -RecurCount $RefreshIntervalHours -Start (Get-Date)

# =============================================================================
# Create one collection per error code
# =============================================================================
$Results = [System.Collections.Generic.List[PSObject]]::new()
$Created = 0
$Skipped = 0
$Failed  = 0

Write-Banner "Creating $($PatchErrors.Count) Device Collections" "Yellow"

foreach ($Err in $PatchErrors) {

    $CollectionName = "Patch Error - $($Err.ShortName) [$($Err.Code)]"

    # WQL query - joins SMS_R_System with WORKSTATION_STATUS on LastErrorCode
    $WqlQuery = @"
select
    SMS_R_System.ResourceId,
    SMS_R_System.ResourceType,
    SMS_R_System.Name,
    SMS_R_System.SMSUniqueIdentifier,
    SMS_R_System.ResourceDomainORWorkgroup,
    SMS_R_System.Client
from
    SMS_R_System
inner join
    SMS_G_System_WORKSTATION_STATUS
    on SMS_G_System_WORKSTATION_STATUS.ResourceID = SMS_R_System.ResourceId
where
    SMS_G_System_WORKSTATION_STATUS.LastErrorCode = $($Err.DecimalCode)
"@

    # Skip if already exists
    $Existing = Get-CMDeviceCollection -Name $CollectionName -ErrorAction SilentlyContinue
    if ($Existing) {
        Write-Step "~" "SKIP  (exists): $CollectionName" "DarkGray"
        $Skipped++
        $Results.Add([PSCustomObject]@{
            ErrorCode   = $Err.Code
            ShortName   = $Err.ShortName
            Collection  = $CollectionName
            Script      = $Err.RemediationScript
            Status      = "Skipped - already exists"
        })
        continue
    }

    Write-Step "+" "Creating: $CollectionName" "Green"

    if ($PSCmdlet.ShouldProcess($CollectionName, "New-CMDeviceCollection")) {
        try {
            $NewCol = New-CMDeviceCollection `
                -Name                   $CollectionName `
                -Comment                "$($Err.Code) | $($Err.Description) | Remediation: $($Err.RemediationScript)" `
                -LimitingCollectionName $LimitingCollectionName `
                -RefreshSchedule        $Schedule `
                -RefreshType            Periodic

            Add-CMDeviceCollectionQueryMembershipRule `
                -CollectionName  $CollectionName `
                -QueryExpression $WqlQuery `
                -RuleName        "Patch Error $($Err.Code)"

            Move-CMObject -FolderPath $FolderPath -InputObject $NewCol

            $Created++
            $Results.Add([PSCustomObject]@{
                ErrorCode   = $Err.Code
                ShortName   = $Err.ShortName
                Collection  = $CollectionName
                Script      = $Err.RemediationScript
                Status      = "Created"
            })
        }
        catch {
            Write-Step "!" "FAILED: $CollectionName - $_" "Red"
            $Failed++
            $Results.Add([PSCustomObject]@{
                ErrorCode   = $Err.Code
                ShortName   = $Err.ShortName
                Collection  = $CollectionName
                Script      = $Err.RemediationScript
                Status      = "Failed: $_"
            })
        }
    }
    else {
        # -WhatIf path
        $Results.Add([PSCustomObject]@{
            ErrorCode   = $Err.Code
            ShortName   = $Err.ShortName
            Collection  = $CollectionName
            Script      = $Err.RemediationScript
            Status      = "WhatIf - would create"
        })
    }
}

# =============================================================================
# Summary
# =============================================================================
Write-Banner "Summary" "Cyan"
Write-Host "  Total catalogued errors : $($PatchErrors.Count)"     -ForegroundColor Cyan
Write-Host "  Collections Created     : $Created"                   -ForegroundColor Green
Write-Host "  Collections Skipped     : $Skipped"                   -ForegroundColor DarkGray
Write-Host "  Failures                : $Failed"                    -ForegroundColor $(if ($Failed -gt 0) { "Red" } else { "Green" })
Write-Host ""

$Results | Format-Table ErrorCode, ShortName, Status -AutoSize

# Export run log
$LogPath = Join-Path $PSScriptRoot "PatchErrorCollections_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$Results | Export-Csv -Path $LogPath -NoTypeInformation -Encoding UTF8
Write-Step ">" "Run log saved: $LogPath" "Cyan"

Set-Location $env:SystemDrive
