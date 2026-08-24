<#
  08-Decommission-OldDC.ps1
  RUN ON: the OLD Server 2012 R2 box.
  RUN WHEN: LAST. Only after a genuine burn-in period (recommend at least
  1-2 weeks) with the new server carrying AD, DNS, DHCP, and file shares
  with no issues found. This is the one irreversible step in the whole
  migration - once this runs, there's no quick rollback to the old DC.

  Do not run this the same day as the rest of the migration. The whole
  point of the "add a second DC, verify, then remove the first" approach
  is that you get a real-world proving period with a safety net still in
  place - don't throw that away by rushing the last step.
#>

param(
    [switch]$IReallyMeanIt
)

if (-not $IReallyMeanIt) {
    Write-Host "This demotes and removes AD DS from $env:COMPUTERNAME permanently."
    Write-Host "Before running this for real, confirm ALL of the following:"
    Write-Host "  [ ] New server has been the only DC/DNS/DHCP/file server for at least 1-2 weeks with no issues"
    Write-Host "  [ ] netdom query fsmo shows the new server holding all 5 FSMO roles"
    Write-Host "  [ ] A full backup of this old server exists, taken AFTER the burn-in period"
    Write-Host "  [ ] Nothing on the network still references this server by name or IP (check DHCP scope option 006, static DNS entries on any devices, mapped drives, printers, backup jobs, line-of-business app configs)"
    Write-Host ""
    Write-Host "If all of that is genuinely true, re-run this script with -IReallyMeanIt to proceed."
    exit 0
}

Write-Host "=== Demoting $env:COMPUTERNAME ==="
Import-Module ADDSDeployment
Uninstall-ADDSDomainController -DemoteOperationMasterRole -RemoveDnsDelegation -Force -Confirm:$false

Write-Host "=== Demotion complete. Server has rebooted as a member server (or standalone, depending on options chosen during the wizard prompts). ==="
Write-Host "Remaining manual cleanup:"
Write-Host "  - Remove this server's old DHCP authorization in AD if not already gone (Get-DhcpServerInDC / Remove-DhcpServerInDC on the new server)"
Write-Host "  - Remove any lingering DNS records/delegations pointing at the old server's name or IP"
Write-Host "  - Decide whether to decommission this hardware entirely or repurpose it"
