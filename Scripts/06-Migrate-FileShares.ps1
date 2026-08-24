<#
  06-Migrate-FileShares.ps1
  RUN ON: the NEW server, but reads FROM the old server over the network
  (needs read access to \\OLDSERVER\<share admin paths> - run as a
  Domain Admin or an account with full read access to the source data).

  RUN TWICE:
    1. Days before cutover, with -FinalPass:$false - does a full copy of
       everything. This is the slow part and causes zero downtime since
       the old shares keep working normally throughout.
    2. During the actual cutover window, with -FinalPass:$true - a much
       faster incremental pass (robocopy /MIR only copies what changed
       since the first pass), followed by recreating the shares
       themselves so clients can start using the new server.

  KNOWN LIMITATION: SMB1/CIFS is deliberately NOT re-enabled on the new
  server by this script, even though it was installed on the old one
  (flagged in 01-Preflight-Checks.ps1). If something old genuinely still
  needs SMB1, that's a deliberate decision to make explicitly, not a
  default to inherit silently.
#>

param(
    [Parameter(Mandatory)][string]$OldServerName,
    [switch]$FinalPass
)

# Read the share inventory captured by 01-Preflight-Checks.ps1
$inventoryPath = "$PSScriptRoot\..\Logs\file-shares-before.csv"
if (-not (Test-Path $inventoryPath)) {
    Write-Error "Share inventory not found at $inventoryPath - run 01-Preflight-Checks.ps1 on the old server first."
    exit 1
}
$shares = Import-Csv $inventoryPath

foreach ($share in $shares) {
    $sourcePath = "\\$OldServerName\$($share.Name)"
    # Mirror shares into an identical folder structure under D:\Shares on
    # the new server - adjust $destRoot if the new server's disk layout differs.
    $destRoot = "D:\Shares\$($share.Name)"

    Write-Host "=== Syncing share '$($share.Name)': $sourcePath -> $destRoot ==="
    if (-not (Test-Path $destRoot)) { New-Item -ItemType Directory -Path $destRoot -Force | Out-Null }

    # /MIR mirrors (including deletions), /COPYALL + /SEC preserve NTFS
    # permissions/owner/timestamps, /MT runs multi-threaded, /ZB handles
    # both normal and restricted-access files, /R:2 /W:5 keep retries short
    # so a single locked file doesn't stall the whole job.
    $logFile = "$PSScriptRoot\..\Logs\robocopy-$($share.Name)-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    robocopy $sourcePath $destRoot /MIR /COPYALL /SEC /ZB /MT:16 /R:2 /W:5 /LOG:$logFile /TEE

    if ($FinalPass) {
        # Recreate the share itself, matching the source's NTFS-level
        # permissions (already copied above via /SEC) and its share-level
        # permissions (queried live from the old server, not from the
        # static CSV, in case anything changed since the pre-flight check).
        $shareAccess = Invoke-Command -ComputerName $OldServerName -ScriptBlock {
            param($ShareName) Get-SmbShareAccess -Name $ShareName
        } -ArgumentList $share.Name

        if (Get-SmbShare -Name $share.Name -ErrorAction SilentlyContinue) {
            Write-Host "Share '$($share.Name)' already exists on this server - skipping share creation, content already synced above."
        }
        else {
            New-SmbShare -Name $share.Name -Path $destRoot -Description $share.Description -FullAccess "Everyone" | Out-Null
            Revoke-SmbShareAccess -Name $share.Name -AccountName "Everyone" -Force
            foreach ($access in $shareAccess) {
                Grant-SmbShareAccess -Name $share.Name -AccountName $access.AccountName -AccessRight $access.AccessRight -Force
            }
            Write-Host "Created share '$($share.Name)' on $env:COMPUTERNAME -> $destRoot with matching share permissions."
        }
    }
}

if ($FinalPass) {
    Write-Host "`n=== Final pass complete. Update any mapped drives/DFS targets/shortcuts that pointed at \\$OldServerName to point at \\$env:COMPUTERNAME instead. ==="
}
else {
    Write-Host "`n=== Initial full sync complete. Old shares are untouched and still serving normally. Run again with -FinalPass during the actual cutover window. ==="
}
