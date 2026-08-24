<#
  02-Promote-NewDC.ps1
  RUN ON: the NEW Server 2016 box.
  RUN WHEN: after it's been built, patched, given a static IP, and joined
  to the domain as a member server, with its preferred DNS pointing at
  the OLD server (itself doesn't have DNS yet at this point).

  This is the step that actually brings the new server into AD - as a
  SECOND domain controller alongside the old one, not a replacement yet.
  The old server keeps working normally throughout this entire step and
  for as long afterward as needed - this is what makes the "very little
  downtime" approach possible: there is no cutover moment here, just
  normal AD replication catching the new DC up in the background.

  Also installs DNS on the new server and, if the zones are AD-integrated
  (the normal case, flagged by 01-Preflight-Checks.ps1), they'll appear
  automatically once replication completes - no separate DNS migration
  step needed for those.
#>

param(
    [Parameter(Mandatory)][string]$DomainName,        # e.g. "makelifeeasy.local"
    [string]$SiteName = "Default-First-Site-Name",
    [string]$DatabasePath = "C:\Windows\NTDS",
    [string]$LogFilePath = "C:\Windows\NTDS",
    [string]$SysvolPath = "C:\Windows\SYSVOL"
)

Write-Host "=== Installing AD DS role on $env:COMPUTERNAME ==="
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

Write-Host "=== Promoting $env:COMPUTERNAME to an additional Domain Controller in $DomainName ==="
Write-Host "You'll be prompted for Domain Admin credentials and a DSRM (Directory Services Restore Mode) password - write the DSRM password down somewhere safe, it's needed for disaster recovery."

Import-Module ADDSDeployment

Install-ADDSDomainController `
    -DomainName $DomainName `
    -Credential (Get-Credential -Message "Enter Domain Admin credentials") `
    -InstallDns:$true `
    -NoGlobalCatalog:$false `
    -SiteName $SiteName `
    -DatabasePath $DatabasePath `
    -LogPath $LogFilePath `
    -SysvolPath $SysvolPath `
    -Force:$true

# Note: the server reboots automatically at the end of promotion.
# After reboot, run 03-Verify-Replication.ps1 before doing anything else.
