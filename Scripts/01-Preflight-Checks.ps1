<#
  01-Preflight-Checks.ps1
  RUN ON: the OLD Server 2012 R2 box.
  RUN WHEN: days before the migration starts. No downtime, read-only checks.

  Confirms the environment is actually ready for a second DC to join,
  before anything is touched. The most important check here is SYSVOL
  replication mode - if it's still on the legacy FRS instead of DFSR,
  that is a HARD BLOCKER: Server 2016 cannot be promoted into a domain
  still using FRS for SYSVOL. FRS was deprecated and removed from newer
  Windows Server entirely - the domain must be migrated to DFSR first
  (a separate, well-documented Microsoft procedure, not covered by this
  toolset) before continuing with this migration at all.

  Also inventories the current DHCP scopes, DNS zones, and file shares,
  so there's a known-good "before" snapshot to compare the new server
  against after each later stage.
#>

param(
    [string]$LogPath = "$PSScriptRoot\..\Logs\01-preflight-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
)

function Write-Check {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    $dir = Split-Path $LogPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -Path $LogPath -Value $line
    Write-Host $line
}

Write-Check "=== Pre-flight checks starting on $env:COMPUTERNAME ==="

# --- 1. SYSVOL replication mode - THE hard blocker to check first ---
Write-Check "Checking SYSVOL replication mode (must be Eliminated/DFSR, not Start/FRS)..."
$dfsrState = dfsrmig /getmigrationstate 2>&1
Write-Check "dfsrmig /getmigrationstate output: $dfsrState"
if ($dfsrState -match "Eliminated") {
    Write-Check "OK - SYSVOL is on DFSR. Safe to proceed."
}
else {
    Write-Check "BLOCKER: SYSVOL does not appear to be fully migrated to DFSR. Server 2016 CANNOT be promoted into this domain until SYSVOL is migrated off FRS. Do not continue past this script until this is resolved (separate Microsoft-documented FRS-to-DFSR migration procedure, not part of this toolset)." -Level "ERROR"
}

# --- 2. Forest / domain functional level ---
Write-Check "Checking forest and domain functional level..."
try {
    $forest = Get-ADForest
    $domain = Get-ADDomain
    Write-Check "Forest functional level: $($forest.ForestMode)"
    Write-Check "Domain functional level: $($domain.DomainMode)"
}
catch {
    Write-Check "Could not query AD forest/domain - is the AD PowerShell module installed (RSAT-AD-PowerShell)? $($_.Exception.Message)" -Level "ERROR"
}

# --- 3. Current DC health ---
Write-Check "Running dcdiag (summary)..."
$dcdiagResult = dcdiag /v 2>&1
$dcdiagResult | Out-File -FilePath "$PSScriptRoot\..\Logs\dcdiag-before.log" -Encoding utf8
$failLines = $dcdiagResult | Select-String "failed"
if ($failLines) {
    Write-Check "dcdiag reported failures - see Logs\dcdiag-before.log for full detail:" -Level "WARN"
    $failLines | ForEach-Object { Write-Check "  $_" -Level "WARN" }
}
else {
    Write-Check "dcdiag: no 'failed' lines found. Full output saved to Logs\dcdiag-before.log"
}

Write-Check "Running repadmin /replsummary..."
$repl = repadmin /replsummary 2>&1
$repl | Out-File -FilePath "$PSScriptRoot\..\Logs\repadmin-before.log" -Encoding utf8
Write-Check "repadmin output saved to Logs\repadmin-before.log"

# --- 4. FSMO role holders (so we know what needs transferring later) ---
Write-Check "Current FSMO role holders:"
$fsmo = netdom query fsmo 2>&1
$fsmo | ForEach-Object { Write-Check "  $_" }

# --- 5. Inventory: DHCP scopes ---
Write-Check "Inventorying DHCP scopes..."
try {
    $scopes = Get-DhcpServerv4Scope
    $scopes | Select-Object ScopeId, Name, StartRange, EndRange, SubnetMask, State |
        Export-Csv "$PSScriptRoot\..\Logs\dhcp-scopes-before.csv" -NoTypeInformation
    Write-Check "$($scopes.Count) DHCP scope(s) found - saved to Logs\dhcp-scopes-before.csv"
}
catch {
    Write-Check "Could not enumerate DHCP scopes: $($_.Exception.Message)" -Level "WARN"
}

# --- 6. Inventory: DNS zones ---
Write-Check "Inventorying DNS zones..."
try {
    $zones = Get-DnsServerZone
    $zones | Select-Object ZoneName, ZoneType, IsDsIntegrated, IsAutoCreated |
        Export-Csv "$PSScriptRoot\..\Logs\dns-zones-before.csv" -NoTypeInformation
    Write-Check "$($zones.Count) DNS zone(s) found - saved to Logs\dns-zones-before.csv"
    $nonAdIntegrated = $zones | Where-Object { -not $_.IsDsIntegrated -and -not $_.IsAutoCreated }
    if ($nonAdIntegrated) {
        Write-Check "$($nonAdIntegrated.Count) zone(s) are NOT AD-integrated - these will need an explicit export/import, they won't replicate automatically:" -Level "WARN"
        $nonAdIntegrated | ForEach-Object { Write-Check "  - $($_.ZoneName)" -Level "WARN" }
    }
}
catch {
    Write-Check "Could not enumerate DNS zones: $($_.Exception.Message)" -Level "WARN"
}

# --- 7. Inventory: file shares (excluding default admin shares) ---
Write-Check "Inventorying file shares..."
try {
    $shares = Get-SmbShare | Where-Object { $_.Name -notmatch '\$$' -and $_.Name -ne 'NETLOGON' -and $_.Name -ne 'SYSVOL' }
    $shares | Select-Object Name, Path, Description | Export-Csv "$PSScriptRoot\..\Logs\file-shares-before.csv" -NoTypeInformation
    Write-Check "$($shares.Count) real file share(s) found - saved to Logs\file-shares-before.csv"
    foreach ($share in $shares) {
        $acl = Get-SmbShareAccess -Name $share.Name
        Write-Check "  Share '$($share.Name)' -> $($share.Path)"
        $acl | ForEach-Object { Write-Check "    $($_.AccountName): $($_.AccessRight) ($($_.AccessControlType))" }
    }
}
catch {
    Write-Check "Could not enumerate file shares: $($_.Exception.Message)" -Level "WARN"
}

# --- 8. SMB1 check - flagged, not auto-disabled ---
$smb1 = Get-WindowsFeature FS-SMB1
if ($smb1.InstallState -eq "Installed") {
    Write-Check "SMB1/CIFS (FS-SMB1) is currently installed on this server - it's an old, insecure protocol. Decide before migration whether anything genuinely still needs it (old scanners/NAS devices sometimes do) - if not, don't carry it forward to the new server." -Level "WARN"
}

Write-Check "=== Pre-flight checks complete. Review Logs\ for full detail and resolve any BLOCKER/WARN items before continuing to stage 2. ==="
