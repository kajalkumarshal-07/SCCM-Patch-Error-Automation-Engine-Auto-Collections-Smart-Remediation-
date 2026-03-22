# SCCM Patch Error — Automated Collection & Remediation

> Automated device collection creation and targeted remediation scripts for Windows Update / SCCM patching failures.
> Built for enterprise environments running Microsoft Endpoint Configuration Manager (SCCM/ConfigMgr).

---

## Overview

This toolkit automates two things that are normally done manually:

1. **Collection creation** — Creates one SCCM Device Collection per known patch error code, each populated by a WQL query against `SMS_G_System_WORKSTATION_STATUS.LastErrorCode`.
2. **Remediation** — A master dispatcher detects the error on an endpoint and calls the correct targeted remediation script automatically.

Covers **29 error codes** across **15 remediation scripts**, including errors captured from a live production environment — Delivery Optimization stalls, SCCM handler job cancellations, XML parse failures, CRC data errors, and more.

---

## Repository Structure

```
├── SCCM_Create-PatchErrorCollections.ps1       # Run once — creates all 29 collections in SCCM
├── SCCM_Master-PatchRemediation.ps1            # Deploy to collections — routes to correct script
│
├── Remediate-0x80070005_AccessDenied.ps1
├── Remediate-0x80070422_WUServiceDisabled.ps1
├── Remediate-0x8024402C_WsusConnectFail.ps1
├── Remediate-0x80070BC9_RebootPending.ps1
├── Remediate-0x80073712_CBSCorrupt.ps1
├── Remediate-0x80070643_MsiFileLocked.ps1
├── Remediate-0x80070002_DownloadFailed.ps1
├── Remediate-0x800B0109_CertChainUntrusted.ps1
├── Remediate-0x800705B4_TimeoutWuaError.ps1
├── Remediate-0x80D02002_DeliveryOptimization.ps1
├── Remediate-0x800F0991_UnknownSFXError.ps1
├── Remediate-0x87D00664_UpdatesHandlerJob.ps1
├── Remediate-0x800705B9_XmlParseError.ps1
├── Remediate-0x8007139F_InvalidState.ps1
└── Remediate-0x80070017_CRC_Shutdown.ps1
```

---

## Error Code Coverage

### Windows Update / WUA

| Error Code | Short Name | Description | Remediation Script |
|---|---|---|---|
| `0x80070005` | AccessDenied | WUA or SCCM agent lacks permission to directories or registry | `Remediate-0x80070005_AccessDenied.ps1` |
| `0x80070422` | WUServiceDisabled | Windows Update service disabled or startup type blocked | `Remediate-0x80070422_WUServiceDisabled.ps1` |
| `0x80070002` | FileNotFound | Source file missing from DP cache or local staging | `Remediate-0x80070002_DownloadFailed.ps1` |
| `0x8007000E` | OutOfMemory | Insufficient memory during update processing | `Remediate-0x800705B4_TimeoutWuaError.ps1` |
| `0x80070017` | CRCDataError | Cyclic Redundancy Check — corrupt cached download on disk | `Remediate-0x80070017_CRC_Shutdown.ps1` |
| `0x80070020` | FileLocked | Update file locked by another process | `Remediate-0x80070643_MsiFileLocked.ps1` |
| `0x80070643` | MsiInstallFailed | Fatal MSI/installer error — orphaned temp files or corrupt state | `Remediate-0x80070643_MsiFileLocked.ps1` |
| `0x800705B4` | Timeout | Operation timed out during download or install | `Remediate-0x800705B4_TimeoutWuaError.ps1` |
| `0x800705B9` | XmlParseError | Cannot parse XML — corrupt `DataStore.edb` or malformed WSUS response | `Remediate-0x800705B9_XmlParseError.ps1` |
| `0x80070BC2` | RebootRequired | Update installed — reboot required to finalise | `Remediate-0x80070BC9_RebootPending.ps1` |
| `0x80070BC9` | RebootPending | Pending reboot blocking further update installation | `Remediate-0x80070BC9_RebootPending.ps1` |
| `0x8007045B` | ShutdownInProgress | System shutdown interrupted an install mid-flight | `Remediate-0x80070017_CRC_Shutdown.ps1` |
| `0x8007139F` | InvalidResourceState | Service group or WUA state machine in invalid/inconsistent state | `Remediate-0x8007139F_InvalidState.ps1` |

### CBS / Component Store

| Error Code | Short Name | Description | Remediation Script |
|---|---|---|---|
| `0x80073712` | CbsComponentCorrupt | Windows Component Store corruption — DISM repair required | `Remediate-0x80073712_CBSCorrupt.ps1` |
| `0x8007371B` | CbsTransactionError | CBS transaction or manifest error during update apply | `Remediate-0x80073712_CBSCorrupt.ps1` |

### WUA Agent Internal

| Error Code | Short Name | Description | Remediation Script |
|---|---|---|---|
| `0x80240010` | WuaCancelled | Update cancelled by user or Group Policy | `Remediate-0x800705B4_TimeoutWuaError.ps1` |
| `0x80240022` | AllUpdatesNotApplicable | All updates not applicable — scan cache or policy mismatch | `Remediate-0x800705B4_TimeoutWuaError.ps1` |
| `0x80240FFF` | WuaUnexpectedError | Unexpected WUA agent error | `Remediate-0x800705B4_TimeoutWuaError.ps1` |
| `0x800F0991` | SFXExtractionError | SFX/cab extraction failure or CBS manifest mismatch | `Remediate-0x800F0991_UnknownSFXError.ps1` |

### WSUS / Software Update Point

| Error Code | Short Name | Description | Remediation Script |
|---|---|---|---|
| `0x80244022` | WsusNoService | WSUS returned HTTP 503 Service Unavailable | `Remediate-0x8024402C_WsusConnectFail.ps1` |
| `0x8024402C` | WsusConnectFail | Cannot connect to WSUS/SUP — proxy or DNS failure | `Remediate-0x8024402C_WsusConnectFail.ps1` |
| `0xC1800118` | WsusDeclined | Update declined on WSUS — approval or policy issue | `Remediate-0x8024402C_WsusConnectFail.ps1` |

### Download / BITS / Distribution Point

| Error Code | Short Name | Description | Remediation Script |
|---|---|---|---|
| `0x80246007` | DownloadFailed | Content download failed — DP unavailable or BITS error | `Remediate-0x80070002_DownloadFailed.ps1` |

### Delivery Optimization

| Error Code | Short Name | Description | Remediation Script |
|---|---|---|---|
| `0x80D02002` | DODownloadStalled | DO download stalled — no progress within the defined time window | `Remediate-0x80D02002_DeliveryOptimization.ps1` |
| `0x80D03805` | DOUnknownError | Delivery Optimization internal unknown error | `Remediate-0x80D02002_DeliveryOptimization.ps1` |

### Certificate / PKI

| Error Code | Short Name | Description | Remediation Script |
|---|---|---|---|
| `0x800B0109` | CertChainUntrusted | Certificate chain issued by untrusted authority — Root CA store needs update | `Remediate-0x800B0109_CertChainUntrusted.ps1` |

### SCCM Client / Handler Job

| Error Code | Short Name | Description | Remediation Script |
|---|---|---|---|
| `0x87D00324` | AppNotDetected | App not detected after install — SCCM detection rule mismatch | `Remediate-0x80070422_WUServiceDisabled.ps1` |
| `0x87D00664` | UpdatesHandlerCancelled | SCCM updates handler job cancelled — stale WUAHandler state | `Remediate-0x87D00664_UpdatesHandlerJob.ps1` |
| `0x87D00665` | NoUpdatesInJob | No updates to process in SCCM handler job — policy/scan sync gap | `Remediate-0x87D00664_UpdatesHandlerJob.ps1` |

---

## Prerequisites

| Requirement | Detail |
|---|---|
| PowerShell | 5.1 or later |
| SCCM Admin Console | Must be installed on the machine running the collection creation script |
| Execution Policy | `Bypass` or `RemoteSigned` on target endpoints |
| Run As | Local Administrator or SYSTEM for remediation scripts |
| SCCM Role | Full Administrator or Collections RBAC role for collection creation |
| Hardware Inventory | `SMS_G_System_WORKSTATION_STATUS` class must be enabled on the site |

---

## Step 1 — Create Device Collections

Run `SCCM_Create-PatchErrorCollections.ps1` **once** from any machine with the SCCM Admin Console installed.

```powershell
# Basic usage
.\SCCM_Create-PatchErrorCollections.ps1 `
    -SiteServer "SCCMSERVER.domain.local" `
    -SiteCode   "PS1"

# Dry run first (recommended before first execution)
.\SCCM_Create-PatchErrorCollections.ps1 `
    -SiteServer "SCCMSERVER.domain.local" `
    -SiteCode   "PS1" `
    -WhatIf

# Custom folder name, limiting collection, and refresh interval
.\SCCM_Create-PatchErrorCollections.ps1 `
    -SiteServer             "SCCMSERVER.domain.local" `
    -SiteCode               "PS1" `
    -ParentFolderName       "Patch Errors" `
    -LimitingCollectionName "All Workstations" `
    -RefreshIntervalHours   6
```

**What it does:**
- Creates **29 Device Collections** under `Device Collections > Patch Error Collections`
- Each collection has a WQL membership rule on `SMS_G_System_WORKSTATION_STATUS.LastErrorCode`
- Each collection comment stores the error description and remediation script name
- Collections refresh membership every 4 hours (configurable)
- Skips any collection that already exists — safe to re-run
- Exports a timestamped CSV run log to the script directory

---

## Step 2 — Deploy Remediation

Copy **all scripts** (master dispatcher + all 15 `Remediate-*.ps1` files) into a single SCCM Package source folder on your DP.

### Option A — One Package, one Program per collection (recommended)

Create one **SCCM Package** pointing to the script source folder. Create one **Program** per error code collection using the command line below, swapping in the appropriate `-ErrorCode` value.

**Program command line template:**
```
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "SCCM_Master-PatchRemediation.ps1" -ErrorCode "0x80070422"
```

| Target Collection | `-ErrorCode` Argument |
|---|---|
| Patch Error - AccessDenied | `-ErrorCode "0x80070005"` |
| Patch Error - WUServiceDisabled | `-ErrorCode "0x80070422"` |
| Patch Error - WsusConnectFail | `-ErrorCode "0x8024402C"` |
| Patch Error - WsusNoService | `-ErrorCode "0x80244022"` |
| Patch Error - WsusDeclined | `-ErrorCode "0xC1800118"` |
| Patch Error - RebootPending | `-ErrorCode "0x80070BC9"` |
| Patch Error - RebootRequired | `-ErrorCode "0x80070BC2"` |
| Patch Error - CbsComponentCorrupt | `-ErrorCode "0x80073712"` |
| Patch Error - CbsTransactionError | `-ErrorCode "0x8007371B"` |
| Patch Error - MsiInstallFailed | `-ErrorCode "0x80070643"` |
| Patch Error - FileLocked | `-ErrorCode "0x80070020"` |
| Patch Error - FileNotFound | `-ErrorCode "0x80070002"` |
| Patch Error - DownloadFailed | `-ErrorCode "0x80246007"` |
| Patch Error - CertChainUntrusted | `-ErrorCode "0x800B0109"` |
| Patch Error - Timeout | `-ErrorCode "0x800705B4"` |
| Patch Error - WuaUnexpectedError | `-ErrorCode "0x80240FFF"` |
| Patch Error - WuaCancelled | `-ErrorCode "0x80240010"` |
| Patch Error - AllUpdatesNotApplicable | `-ErrorCode "0x80240022"` |
| Patch Error - OutOfMemory | `-ErrorCode "0x8007000E"` |
| Patch Error - DODownloadStalled | `-ErrorCode "0x80D02002"` |
| Patch Error - DOUnknownError | `-ErrorCode "0x80D03805"` |
| Patch Error - SFXExtractionError | `-ErrorCode "0x800F0991"` |
| Patch Error - UpdatesHandlerCancelled | `-ErrorCode "0x87D00664"` |
| Patch Error - NoUpdatesInJob | `-ErrorCode "0x87D00665"` |
| Patch Error - XmlParseError | `-ErrorCode "0x800705B9"` |
| Patch Error - InvalidResourceState | `-ErrorCode "0x8007139F"` |
| Patch Error - CRCDataError | `-ErrorCode "0x80070017"` |
| Patch Error - ShutdownInProgress | `-ErrorCode "0x8007045B"` |
| Patch Error - AppNotDetected | `-ErrorCode "0x87D00324"` |

### Option B — Auto-detect mode

Deploy without `-ErrorCode` to let the dispatcher query WMI for the last error automatically. Useful as a catch-all deployed to a broad collection.

```
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "SCCM_Master-PatchRemediation.ps1"
```

Detection order:
1. `CCM_SoftwareUpdate` WMI class (`root\ccm\clientsdk`)
2. Windows Update registry fallback (`HKLM:\...\Results\Install\LastError`)
3. Generic WUA reset if neither returns a known code

### Option C — SCCM Scripts (no package required)

For SCCM 1706 or later, upload individual `Remediate-*.ps1` scripts via **Administration > Scripts** and run them directly against the matching collection from the SCCM console.

---

## Deployment Settings

| Setting | Recommended Value |
|---|---|
| Run As | SYSTEM |
| Allow users to interact | No |
| Maximum run time | 60 min (90 min for CBS collections) |
| Estimated install time | 5–10 min |
| Rerun behaviour | Always rerun |
| Allow fallback to unprotected DP | Yes |

> **CBS repair collections** (`0x80073712`, `0x8007371B`): DISM RestoreHealth can take up to 45 minutes on heavily degraded systems. Set maximum run time to **90 minutes** for these two deployments. Deploy as a Package, not a Script.

---

## What Each Remediation Script Does

### `Remediate-0x80070005_AccessDenied.ps1`
Resets ACLs on `SoftwareDistribution` and `CCM\Cache`, sets `wuauserv` to run as LocalSystem, re-registers WUA DLLs, restarts services, triggers policy and scan cycles.

### `Remediate-0x80070422_WUServiceDisabled.ps1`
Sets correct startup types for `wuauserv`, BITS, `CryptSvc`, and `TrustedInstaller`. Removes `NoAutoUpdate` Group Policy registry override. Starts all services.

### `Remediate-0x8024402C_WsusConnectFail.ps1`
Removes stale `WUServer`/`WUStatusServer`/`SusClientId` registry values. Resets WinHTTP proxy (`netsh winhttp reset proxy`). Imports IE proxy into WinHTTP if one is configured. Flushes DNS, resets Winsock.

### `Remediate-0x80070BC9_RebootPending.ps1`
Clears all pending-reboot registry keys: WU `RebootRequired`, CBS `PackagesPending`, Session Manager `PendingFileRenameOperations`, and the SCCM `RebootData` key. Supports optional `-ForceReboot` switch.

### `Remediate-0x80073712_CBSCorrupt.ps1`
Runs DISM `CheckHealth` → `ScanHealth` → `RestoreHealth`. Accepts `-WimSource` parameter for offline repair. Runs `SFC /scannow` after DISM. Runs `StartComponentCleanup` to trim stale packages. **Allow 90 minutes runtime.**

### `Remediate-0x80070643_MsiFileLocked.ps1`
Stops `msiserver`, removes orphaned `*.tmp`/`*.msi`/`*.msp` files, clears SCCM CCM content cache via COM, terminates known file-locking processes, re-registers msiexec (`/unregserver` + `/regserver`).

### `Remediate-0x80070002_DownloadFailed.ps1`
Stops BITS and `wuauserv`. Clears `SoftwareDistribution\Download`. Cancels all BITS transfer jobs and removes the BITS queue database. Clears SCCM CCM content cache to force a re-download from the DP.

### `Remediate-0x800B0109_CertChainUntrusted.ps1`
Runs `certutil -syncWithWU` to refresh the Root CA store. Generates and imports an SST from Windows Update. Resets the certificate chain engine cache and SSL session cache. Restarts `CryptSvc`.

### `Remediate-0x800705B4_TimeoutWuaError.ps1`
Clears `SoftwareDistribution\DataStore` and `Download`. Removes stale SCCM CI store files (`CIStore.sdf`, `CIStateStore.sdf`). Re-registers WUA DLLs. Triggers a clean full scan cycle.

### `Remediate-0x80D02002_DeliveryOptimization.ps1`
Stops `DoSvc`, clears the Delivery Optimization cache, sets DO download mode to HTTP-only (`DODownloadMode = 0`) to bypass P2P, cancels stale BITS jobs, clears `SoftwareDistribution\Download`. Includes a note to re-enable P2P via Group Policy after patching if required.

### `Remediate-0x800F0991_UnknownSFXError.ps1`
Checks free disk space — runs Disk Cleanup if under 2 GB. Clears CBS expansion staging paths (`\Temp\CBS`, `\CbsTemp`). Runs DISM `CheckHealth` and `RestoreHealth` if the component store reports issues. Restarts `TrustedInstaller`, BITS, `wuauserv`.

### `Remediate-0x87D00664_UpdatesHandlerJob.ps1`
Stops `ccmexec`. Clears the SCCM state message store, `SoftwareDistribution`, and `Temp` paths. Removes stale CI store databases (`CIStore.sdf`, `CIStateStore.sdf`, `CITaskStore.sdf`) so they rebuild on agent restart. Triggers Machine Policy, Policy Evaluation, Software Updates Scan, and Deployment Evaluation cycles in sequence.

### `Remediate-0x800705B9_XmlParseError.ps1`
Deletes `DataStore.edb` — the primary cause of repeated XML parse failures. Re-registers `msxml3.dll`, `msxml6.dll`, and core WUA DLLs. Resets WinHTTP proxy and flushes the DNS cache.

### `Remediate-0x8007139F_InvalidState.ps1`
Terminates hung `wuauclt`, `TrustedInstaller`, and `msiexec` processes. Stops the full update service group in dependency order. Resets service start types to expected values via `sc.exe`. Restarts services in the correct dependency order and triggers a fresh policy and scan cycle.

### `Remediate-0x80070017_CRC_Shutdown.ps1`
Runs `chkdsk /scan` (read-only surface check) and logs the result. Clears corrupt cached downloads from `SoftwareDistribution\Download`. Clears SCCM CCM cache and cancels BITS jobs.
For `0x8007045B` additionally: removes CBS `SessionsPending` keys left by the interrupted shutdown, clears the WU `RebootRequired` flag, and runs `SFC /scannow` to repair any partially-written files.

---

## Log Files

All scripts write to `C:\Windows\Temp\`:

| Log File | Written By |
|---|---|
| `PatchRemediation_Master.log` | Master dispatcher (all runs) |
| `PatchRemediation_AccessDenied.log` | `0x80070005` |
| `PatchRemediation_WUSvcDisabled.log` | `0x80070422` |
| `PatchRemediation_WSUSConnect.log` | `0x8024402C`, `0x80244022` |
| `PatchRemediation_RebootPending.log` | `0x80070BC9`, `0x80070BC2` |
| `PatchRemediation_CBSCorrupt.log` | `0x80073712`, `0x8007371B` |
| `PatchRemediation_MSILock.log` | `0x80070643`, `0x80070020` |
| `PatchRemediation_DownloadFail.log` | `0x80070002`, `0x80246007` |
| `PatchRemediation_CertTrust.log` | `0x800B0109` |
| `PatchRemediation_Timeout.log` | `0x800705B4`, `0x80240FFF`, `0x80240010`, `0x80240022`, `0x8007000E` |
| `PatchRemediation_DeliveryOpt.log` | `0x80D02002`, `0x80D03805` |
| `PatchRemediation_0x800F0991.log` | `0x800F0991` |
| `PatchRemediation_HandlerJob.log` | `0x87D00664`, `0x87D00665` |
| `PatchRemediation_XmlParse.log` | `0x800705B9` |
| `PatchRemediation_0x8007139F.log` | `0x8007139F` |
| `PatchRemediation_CRC_Shutdown.log` | `0x80070017`, `0x8007045B` |

DISM writes its own log to: `C:\Windows\Logs\DISM\dism.log`

---

## SCCM Trigger Schedule GUIDs

Used inside the scripts when calling `Invoke-WmiMethod` to trigger SCCM client cycles:

| GUID | Cycle Name |
|---|---|
| `{00000000-0000-0000-0000-000000000021}` | Machine Policy Retrieval & Evaluation |
| `{00000000-0000-0000-0000-000000000022}` | Machine Policy Evaluation |
| `{00000000-0000-0000-0000-000000000113}` | Software Updates Scan Cycle |
| `{00000000-0000-0000-0000-000000000114}` | Software Updates Deployment Evaluation |

---

## Adding a New Error Code

1. Get the unsigned decimal equivalent of the hex code:
```powershell
[uint32]"0x80D02002"   # returns 2160919554
```

2. Add an entry to `$PatchErrors` in `SCCM_Create-PatchErrorCollections.ps1`:
```powershell
@{
    Code              = "0xXXXXXXXX"
    ShortName         = "YourShortName"
    Description       = "What this error means"
    DecimalCode       = 1234567890
    RemediationScript = "Remediate-0xXXXXXXXX_YourShortName.ps1"
}
```

3. Add a mapping entry to `$RemediationMap` in `SCCM_Master-PatchRemediation.ps1`:
```powershell
"0xXXXXXXXX" = @{ Script = "Remediate-0xXXXXXXXX_YourShortName.ps1"
                   Desc   = "Human-readable description" }
```

4. Create `Remediate-0xXXXXXXXX_YourShortName.ps1` following the same structure as existing scripts — `Write-Log` function, numbered steps, service restarts, and SCCM trigger cycles at the end.

---

## License

MIT — free to use, adapt, and distribute. Attribution appreciated.

---

*Maintained by IT Engineering*
