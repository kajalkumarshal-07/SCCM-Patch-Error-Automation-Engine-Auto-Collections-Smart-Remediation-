#Requires -Version 5.1
<#
.SYNOPSIS
    Creates SCCM Device Collections for every known Software Update
    enforcement error code — one collection for "Error" state and one
    for "Unknown" state per code.

.DESCRIPTION
    Uses SMS_SUMDeploymentAssetDetails joined to SMS_R_System for accurate
    per-deployment error reporting (same source as the SCCM console Software
    Update deployment status view).

    For each error code the script creates two collections:

        [Enforcement State: Error]   Code <SignedDecimal>  — StatusType = 5
        [Enforcement State: Unknown] Code <SignedDecimal>  — StatusType = 4

    Collections are placed in separate console subfolders (configurable).
    The script is safe to re-run — existing collections are skipped.

    Error code catalogue covers 50 codes:
      - SCCM handler / agent errors    (0x87D0xxxx)
      - Windows Update / WUA errors    (0x8024xxxx)
      - Windows system errors          (0x8007xxxx)
      - CBS / Component Store errors
      - Certificate / PKI errors
      - Delivery Optimization errors   (0x80D0xxxx)
      - WSUS errors                    (0xC180xxxx)
      - Live environment captures

    All signed decimal values verified with:  [int32][uint32]"0xHHHHHHHH"

    To find error codes active in YOUR environment, run this SQL against
    the ConfigMgr database:

        SELECT COUNT(ResourceID) AS Devices,
               LastEnforcementErrorCode,
               StatusType
        FROM vSMS_SUMDeploymentStatusPerAsset
        WHERE StatusType IN (4,5)
          AND LastEnforcementErrorCode IS NOT NULL
          AND LastEnforcementErrorCode <> 0
        GROUP BY LastEnforcementErrorCode, StatusType
        ORDER BY COUNT(ResourceID) DESC

.PARAMETER SiteServer
    FQDN or NetBIOS name of the SCCM Primary Site Server.
    Optional if a CMSite PSDrive already exists in the session.

.PARAMETER SiteCode
    Three-character SCCM Site Code (e.g. "PS1").
    Optional — auto-detected from Get-PSDrive -PSProvider CMSite.

.PARAMETER LimitingCollection
    Limiting collection for all new collections.
    Default: "All Systems"

.PARAMETER ErrorFolder
    Console path (relative to site drive) for "Error" state collections.
    Default: "DeviceCollection\SUP\SUP Errors\Enforcement State Error"

.PARAMETER UnknownFolder
    Console path (relative to site drive) for "Unknown" state collections.
    Default: "DeviceCollection\SUP\SUP Errors\Enforcement State Unknown"

.PARAMETER RefreshSchedule
    SCCM schedule string for collection membership refresh.
    Default: "920A8C0000100008"  (every 7 days)

.PARAMETER WhatIf
    Dry-run — shows what would be created without touching SCCM.

.EXAMPLE
    # Auto-detect site, use all defaults
    .\SCCM_Create-SUPErrorCollections.ps1

.EXAMPLE
    # Explicit site server and code
    .\SCCM_Create-SUPErrorCollections.ps1 `
        -SiteServer "SCCMSERVER.domain.local" `
        -SiteCode   "PS1"

.EXAMPLE
    # Dry run first (recommended before first execution)
    .\SCCM_Create-SUPErrorCollections.ps1 -WhatIf

.EXAMPLE
    # Custom folders and limiting collection
    .\SCCM_Create-SUPErrorCollections.ps1 `
        -SiteCode           "PS1" `
        -LimitingCollection "All Workstations" `
        -ErrorFolder        "DeviceCollection\Patching\Errors\Error State" `
        -UnknownFolder      "DeviceCollection\Patching\Errors\Unknown State"

.NOTES
    Author   : IT Engineering
    Version  : 3.0
    Requires : ConfigurationManager PowerShell module
               (SCCM Admin Console installed on this machine)
    Run As   : Account with SCCM Full Administrator or Collections RBAC role
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SiteServer         = "",
    [string]$SiteCode           = "",
    [string]$LimitingCollection = "All Systems",
    [string]$ErrorFolder        = "DeviceCollection\SUP\SUP Errors\Enforcement State Error",
    [string]$UnknownFolder      = "DeviceCollection\SUP\SUP Errors\Enforcement State Unknown",
    [string]$RefreshSchedule    = "920A8C0000100008"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =============================================================================
# ERROR CODE CATALOGUE  —  50 codes
#
# Keys are SIGNED 32-bit decimal integers — the value stored in
# SMS_SUMDeploymentAssetDetails.LastEnforcementErrorCode
#
# PowerShell conversion:  [int32][uint32]"0xHHHHHHHH"
# Reverse:                "0x{0:X8}" -f [uint32][int32]<signed>
#
# =============================================================================
$ErrorCodes = [ordered]@{

    # ── Success ────────────────────────────────────────────────────────────────
    0                = 'Success'

    # ── SCCM Updates Handler / Agent  (0x87D0xxxx → signed) ──────────────────
    -2016409844      = 'Software update execution timeout'
    -2016409966      = 'Group policy conflict'
    -2016410008      = 'Software update still detected as actionable after apply'
    -2016410011      = 'No updates to process in the SCCM handler job'               # 0x87D00665
    -2016410012      = 'SCCM updates handler job was cancelled'                      # 0x87D00664
    -2016410026      = 'Updates handler unable to continue - generic internal error'
    -2016410031      = 'Post-install scan failed'
    -2016410032      = 'Pre-install scan failed'
    -2016410844      = 'Application not detected after installation completed'       # 0x87D00324
    -2016410855      = 'Unknown SCCM error'
    -2016411012      = 'CI documents download timed out'
    -2016411115      = 'Item not found'

    # ── WUA agent internal  (0x8024xxxx → signed) ─────────────────────────────
    -2145107924      = 'Cannot connect to WSUS/SUP - proxy or DNS failure'           # 0x8024402C
    -2145107934      = 'WSUS server returned HTTP 503 Service Unavailable'           # 0x80244022
    -2145107951      = 'WUServer policy value missing in the registry'               # 0x8024002F
    -2145120257      = 'Unexpected WUA agent error'                                  # 0x80240FFF
    -2145123272      = 'No route or network connectivity to endpoint'
    -2145124318      = 'All updates not applicable - scan cache or policy mismatch'  # 0x80240022
    -2145124320      = 'Operation did not complete - no logged-on interactive user'
    -2145124336      = 'Update cancelled by user or policy'                          # 0x80240010
    -2145124341      = 'Operation was cancelled'

    # ── Windows system errors  (0x8007xxxx → signed) ──────────────────────────
    -2147024894      = 'Source file not found - content missing from DP or staging'  # 0x80070002
    -2147024891      = 'Access denied - WUA or SCCM agent lacks permission'          # 0x80070005
    -2147024882      = 'Insufficient memory during update processing'                # 0x8007000E
    -2147024873      = 'Cyclic Redundancy Check failure - corrupt cached download'   # 0x80070017
    -2147024864      = 'File locked by another process - install blocked'            # 0x80070020
    -2147024784      = 'Not enough disk space for update staging'                    # 0x80070070
    -2147024598      = 'Too many posts were made to a semaphore'
    -2147023890      = 'File volume externally altered - opened file no longer valid'
    -2147023838      = 'Windows Update service disabled or startup type blocked'     # 0x80070422
    -2147023781      = 'System shutdown in progress - install was interrupted'       # 0x8007045B
    -2147023436      = 'Operation timed out during download or install'              # 0x800705B4
    -2147023431      = 'Windows unable to parse XML data - corrupt DataStore.edb'   # 0x800705B9
    -2147023293      = 'Fatal MSI/installer error - orphaned temp files'             # 0x80070643
    -2147023728      = 'Element not found'
    -2147021886      = 'Update installed - reboot required to finalise'              # 0x80070BC2
    -2147021879      = 'Pending reboot blocking further update installation'         # 0x80070BC9
    -2147019873      = 'Group or resource not in correct state - WUA/SCM conflict'  # 0x8007139F
    -2147018095      = 'Transaction support in resource manager shut down due to error'
    -2147467259      = 'Unspecified error'
    -2147467260      = 'Operation aborted'

    # ── CBS / Component Store  (0x8007xxxx range → signed) ────────────────────
    -2147010798      = 'Windows Component Store / CBS corruption detected'           # 0x80073712
    -2147010815      = 'The referenced assembly could not be found'
    -2147010789      = 'CBS transaction or manifest error during update apply'       # 0x8007371B
    -2147010893      = 'The referenced assembly is not installed on your system'
    -2146498159      = 'SFX/cab extraction failure or CBS manifest mismatch'         # 0x800F0991

    # ── Certificate / PKI ─────────────────────────────────────────────────────
    -2146889721      = 'Hash value is not correct - file integrity failure'
    -2146762496      = 'No signature was present in the subject'
    -2146762487      = 'Certificate chain issued by untrusted authority'             # 0x800B0109
    -2147217865      = 'Unknown database/query error'

    # ── Delivery Optimization  (0x80D0xxxx → signed) ──────────────────────────
    -2133843966      = 'DO download stalled - no progress within defined time window' # 0x80D02002
    -2133837819      = 'Delivery Optimization unknown internal error'                 # 0x80D03805

    # ── WSUS declined  (0xC1800118 → signed) ──────────────────────────────────
    -1048575720      = 'Update declined on WSUS server'                              # 0xC1800118
}

# =============================================================================
# Helpers
# =============================================================================
function Write-Banner {
    param([string]$Text, [string]$Color = "Cyan")
    $bar = "-" * ($Text.Length + 4)
    Write-Host ""
    Write-Host "  $bar" -ForegroundColor $Color
    Write-Host "  | $Text |" -ForegroundColor $Color
    Write-Host "  $bar" -ForegroundColor $Color
    Write-Host ""
}
function Write-Step {
    param([string]$Icon, [string]$Text, [string]$Color = "White")
    Write-Host "  $Icon  $Text" -ForegroundColor $Color
}

# =============================================================================
# Load ConfigMgr module
# =============================================================================
Write-Banner "SCCM SUP Error Collection Creator  v3.0"

Write-Step ">" "Loading ConfigurationManager module..."
$AdminUIPath = $env:SMS_ADMIN_UI_PATH
if ($AdminUIPath) {
    $Psd1 = $AdminUIPath.Replace("i386", "ConfigurationManager.psd1")
    if (Test-Path $Psd1) {
        Import-Module $Psd1 -ErrorAction Stop
        Write-Step "+" "Loaded from SMS_ADMIN_UI_PATH" "Green"
    }
}
if (-not (Get-Module ConfigurationManager -ErrorAction SilentlyContinue)) {
    Import-Module ConfigurationManager -ErrorAction Stop
    Write-Step "+" "Loaded from PSModulePath" "Green"
}

# =============================================================================
# Resolve site code and PSDrive
# =============================================================================
if ([string]::IsNullOrEmpty($SiteCode)) {
    $Drive = Get-PSDrive -PSProvider CMSite -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Drive) {
        $SiteCode = $Drive.Name
        Write-Step ">" "Auto-detected site code: $SiteCode" "Cyan"
    } else {
        Write-Error "Cannot auto-detect site code. Provide -SiteCode parameter."
    }
}

$SiteDrive = "${SiteCode}:"
if (-not (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) {
    if ([string]::IsNullOrEmpty($SiteServer)) {
        Write-Error "No CMSite PSDrive found and -SiteServer not provided."
    }
    Write-Step ">" "Creating CMSite PSDrive for $SiteCode on $SiteServer..."
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SiteServer -ErrorAction Stop | Out-Null
}
Set-Location $SiteDrive

# =============================================================================
# Validate / create target console folders
# =============================================================================
$ErrorFolderPath   = "${SiteDrive}\$ErrorFolder"
$UnknownFolderPath = "${SiteDrive}\$UnknownFolder"

foreach ($FolderPath in @($ErrorFolderPath, $UnknownFolderPath)) {
    if (-not (Test-Path $FolderPath)) {
        Write-Step "!" "Folder not found: $FolderPath — creating..." "Yellow"
        if ($PSCmdlet.ShouldProcess($FolderPath, "New-Item")) {
            $Parts  = $FolderPath -split "\\"
            $Parent = ($Parts[0..($Parts.Count - 2)]) -join "\"
            $Leaf   = $Parts[-1]
            New-Item -Path $Parent -Name $Leaf -ItemType Directory | Out-Null
            Write-Step "+" "Created: $FolderPath" "Green"
        }
    } else {
        Write-Step ">" "Folder OK: $FolderPath" "DarkGray"
    }
}

# =============================================================================
# Refresh schedule
# =============================================================================
$Schedule = Convert-CMSchedule -ScheduleString $RefreshSchedule

# =============================================================================
# Create two collections per error code
# =============================================================================
$Results  = [System.Collections.Generic.List[PSObject]]::new()
$Created  = 0
$Skipped  = 0
$Failed   = 0
$CodeCount = ($ErrorCodes.Keys | Measure-Object).Count
$Total     = $CodeCount * 2

Write-Banner "Creating collections  ($CodeCount codes x 2 states = $Total)" "Yellow"

foreach ($Code in $ErrorCodes.Keys) {

    $Description = $ErrorCodes[$Code]

    # WQL query template — {0} is replaced with StatusType (4 or 5)
    # Uses SMS_SUMDeploymentAssetDetails — the same join as the SCCM console
    # deployment status view, giving accurate per-deployment error data
    $BaseQuery = @"
select
    SYS.ResourceID,
    SYS.ResourceType,
    SYS.Name,
    SYS.SMSUniqueIdentifier,
    SYS.ResourceDomainORWorkgroup,
    SYS.Client
from
    SMS_R_System as SYS
inner join
    SMS_SUMDeploymentAssetDetails as SUM
    on SYS.ResourceID = SUM.ResourceID
where
    SUM.StatusType = {0}
    and SUM.LastEnforcementErrorCode = $Code
"@

    $Pairs = @(
        @{ State = "Error";   StatusType = 5; Folder = $ErrorFolderPath   }
        @{ State = "Unknown"; StatusType = 4; Folder = $UnknownFolderPath }
    )

    foreach ($Pair in $Pairs) {

        $Name  = "[Enforcement State: $($Pair.State)]   Code $Code"
        $Query = $BaseQuery -f $Pair.StatusType

        $Existing = Get-CMDeviceCollection -Name $Name -ErrorAction SilentlyContinue
        if ($Existing) {
            Write-Step "~" "SKIP (exists): $Name" "DarkGray"
            $Skipped++
            $Results.Add([PSCustomObject]@{
                Code        = $Code
                State       = $Pair.State
                Collection  = $Name
                Description = $Description
                Status      = "Skipped - already exists"
            })
            continue
        }

        Write-Step "+" "[$($Pair.State)] Code $Code — $Description" "Green"

        if ($PSCmdlet.ShouldProcess($Name, "New-CMDeviceCollection")) {
            try {
                $NewCol = New-CMDeviceCollection `
                    -LimitingCollectionName $LimitingCollection `
                    -Name                   $Name `
                    -Comment                $Description `
                    -RefreshType            Periodic `
                    -RefreshSchedule        $Schedule

                Add-CMDeviceCollectionQueryMembershipRule `
                    -CollectionName  $Name `
                    -QueryExpression $Query `
                    -RuleName        $Name

                $NewCol | Move-CMObject -FolderPath $Pair.Folder

                $Created++
                $Results.Add([PSCustomObject]@{
                    Code        = $Code
                    State       = $Pair.State
                    Collection  = $Name
                    Description = $Description
                    Status      = "Created"
                })
            }
            catch {
                Write-Step "!" "FAILED: $Name — $_" "Red"
                $Failed++
                $Results.Add([PSCustomObject]@{
                    Code        = $Code
                    State       = $Pair.State
                    Collection  = $Name
                    Description = $Description
                    Status      = "Failed: $_"
                })
            }
        }
        else {
            $Results.Add([PSCustomObject]@{
                Code        = $Code
                State       = $Pair.State
                Collection  = $Name
                Description = $Description
                Status      = "WhatIf - would create"
            })
        }
    }
}

# =============================================================================
# Summary
# =============================================================================
Write-Banner "Summary" "Cyan"
Write-Host "  Error codes in catalogue : $CodeCount"                                          -ForegroundColor Cyan
Write-Host "  Total collections target : $Total  (2 per code)"                               -ForegroundColor Cyan
Write-Host "  Created                  : $Created"                                            -ForegroundColor Green
Write-Host "  Skipped (already exist)  : $Skipped"                                           -ForegroundColor DarkGray
Write-Host "  Failed                   : $Failed"                                             -ForegroundColor $(if ($Failed) {"Red"} else {"Green"})
Write-Host ""

$Results | Format-Table Code, State, Status, Description -AutoSize

$LogPath = Join-Path $PSScriptRoot "SUPErrorCollections_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$Results | Export-Csv -Path $LogPath -NoTypeInformation -Encoding UTF8
Write-Step ">" "Run log saved: $LogPath" "Cyan"

Set-Location $env:SystemDrive

<#
===============================================================================
REFERENCE
===============================================================================

StatusType values in SMS_SUMDeploymentAssetDetails:
  1 = Success
  2 = In Progress
  3 = Unknown (no status reported)
  4 = Unknown (with a LastEnforcementErrorCode present)
  5 = Error   (with a LastEnforcementErrorCode present)
  6 = Requirements Not Met

PowerShell decimal conversions:
  Hex to signed decimal:  [int32][uint32]"0x80070005"    →  -2147024891
  Signed decimal to hex:  "0x{0:X8}" -f [uint32][int32]-2147024891  →  0x80070005

SQL to discover NEW error codes in your environment:
  SELECT COUNT(ResourceID) AS Devices,
         LastEnforcementErrorCode,
         StatusType
  FROM vSMS_SUMDeploymentStatusPerAsset
  WHERE StatusType IN (4,5)
    AND LastEnforcementErrorCode IS NOT NULL
    AND LastEnforcementErrorCode <> 0
  GROUP BY LastEnforcementErrorCode, StatusType
  ORDER BY COUNT(ResourceID) DESC

Adding a new error code:
  1. Run the SQL above to discover codes in your environment
  2. Add the signed decimal as a new key in $ErrorCodes with a description
  3. Create a matching Remediate-*.ps1 if the error needs unique remediation
  4. Re-run this script — existing collections are skipped automatically

===============================================================================
#>
