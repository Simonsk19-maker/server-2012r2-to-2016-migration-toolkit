<#
  04a-Export-DHCP-OldServer.ps1
  RUN ON: the OLD Server 2012 R2 box.
  RUN WHEN: after replication is verified clean (stage 3). This step is
  read-only on the old server - it does NOT touch or deactivate anything,
  so there's no downtime risk here yet.

  Exports every scope, reservation, lease, option, superscope, and
  policy in one file using DHCP's own native migration cmdlet - this is
  the one piece of "migration" that's genuinely just correctly using
  Microsoft's own supported tool, not custom logic.
#>

param(
    [string]$ExportFile = "C:\DHCPMigration\dhcp-export.xml"
)

$dir = Split-Path $ExportFile -Parent
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

Write-Host "=== Exporting DHCP configuration from $env:COMPUTERNAME ==="
Export-DhcpServer -File $ExportFile -Leases -Verbose

Write-Host "Export complete: $ExportFile"
Write-Host "Copy this file to the new server, then run 04b-Import-DHCP-NewServer.ps1 there."
Write-Host "The old DHCP server has NOT been touched or deactivated by this script - it's still serving normally."
