<#
  03-Verify-Replication.ps1
  RUN ON: either server (uses AD PowerShell to query both).
  RUN WHEN: after the new server has rebooted post-promotion, and
  periodically for the following hour or so until everything shows clean.

  STOP AND VERIFY point - do not move on to DHCP/file/FSMO work until
  this comes back clean. Replication problems are much easier to fix
  while both DCs are still up and the old one hasn't been touched.
#>

param(
    [string]$NewDCName = $env:COMPUTERNAME
)

Write-Host "=== Verifying AD replication involving $NewDCName ==="

Write-Host "`n--- dcdiag /v ---"
dcdiag /v

Write-Host "`n--- repadmin /replsummary ---"
repadmin /replsummary

Write-Host "`n--- repadmin /showrepl $NewDCName ---"
repadmin /showrepl $NewDCName

Write-Host "`n--- Domain controllers now in the domain ---"
Get-ADDomainController -Filter * | Select-Object Name, IPv4Address, OperatingSystem, IsGlobalCatalog, Site

Write-Host "`n--- DNS zones on $NewDCName (compare against Logs\dns-zones-before.csv from the old server) ---"
Get-DnsServerZone -ComputerName $NewDCName | Select-Object ZoneName, ZoneType, IsDsIntegrated

Write-Host "`n--- SYSVOL contents on the new server (spot-check against \\OLDSERVER\SYSVOL manually) ---"
Get-ChildItem "\\$NewDCName\SYSVOL" -ErrorAction SilentlyContinue

Write-Host "`n=== Checklist before moving to the next stage ==="
Write-Host "[ ] dcdiag shows no failures"
Write-Host "[ ] repadmin /replsummary shows 0 fails, low USN deltas settling toward 0"
Write-Host "[ ] New DC appears in Get-ADDomainController output with the expected IP"
Write-Host "[ ] DNS zone list on the new server matches the old server's zone list"
Write-Host "[ ] SYSVOL contents on the new server visually match the old server's SYSVOL"
Write-Host "Do not proceed to DHCP/FSMO/file migration until every box above is genuinely checked, not assumed."
