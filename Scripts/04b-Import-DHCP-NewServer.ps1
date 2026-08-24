<#
  04b-Import-DHCP-NewServer.ps1
  RUN ON: the NEW Server 2016 box.
  RUN WHEN: after copying the export file from the old server here.

  Imports the DHCP configuration and authorizes this server in AD, but
  deliberately does NOT activate the scopes yet - that happens in
  05-Cutover-DHCP-Scopes.ps1, as its own controlled step, because having
  two DHCP servers both actively answering for the same scope at the
  same time risks duplicate/conflicting leases. Import first, verify,
  THEN cut over.
#>

param(
    [Parameter(Mandatory)][string]$ImportFile   # e.g. "C:\DHCPMigration\dhcp-export.xml", copied from the old server
)

if (-not (Test-Path $ImportFile)) {
    Write-Error "Import file not found at $ImportFile - copy it from the old server first (see 04a-Export-DHCP-OldServer.ps1)."
    exit 1
}

Write-Host "=== Installing DHCP role on $env:COMPUTERNAME ==="
Install-WindowsFeature DHCP -IncludeManagementTools

Write-Host "=== Authorizing $env:COMPUTERNAME as a DHCP server in AD ==="
Add-DhcpServerInDC -DnsName "$env:COMPUTERNAME.$env:USERDNSDOMAIN"

Write-Host "=== Importing DHCP configuration from $ImportFile ==="
Import-DhcpServer -File $ImportFile -BackupPath "C:\DHCPMigration\ImportBackup" -Verbose

Write-Host "=== Scopes imported (currently INACTIVE by default after import - do not activate yet) ==="
Get-DhcpServerv4Scope | Select-Object ScopeId, Name, State

Write-Host ""
Write-Host "Scopes are imported but not yet serving clients. Next step: 05-Cutover-DHCP-Scopes.ps1"
Write-Host "which deactivates the OLD server's scopes and activates these ones in a controlled sequence."
