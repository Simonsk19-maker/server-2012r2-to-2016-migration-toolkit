<#
  05-Cutover-DHCP-Scopes.ps1
  RUN: this is the one genuine "moment of risk" step in the whole
  migration - the closest thing to actual downtime. Budget a short
  maintenance window for it even though it only takes a minute or two,
  ideally outside working hours.

  THE RULE: never have both servers actively answering DHCP for the same
  scope at the same time - that risks two clients getting the same IP.
  So this script deactivates the OLD server's scope(s) FIRST, confirms
  it, THEN activates the NEW server's scope(s). Run it once against the
  old server with -Action Deactivate, confirm scopes show Inactive, then
  immediately run it against the new server with -Action Activate.

  Existing clients keep their current leases and keep working normally
  either way - this only affects servers issuing NEW leases/renewals.
  Nothing user-facing breaks the moment you run this; it just changes
  which server answers the next DHCP request.

  ROLLBACK: if anything looks wrong after activating the new server, you
  can immediately reverse this - reactivate the old server's scopes and
  deactivate the new one's - since the old server hasn't been decommissioned
  yet at this stage.
#>

param(
    [Parameter(Mandatory)][ValidateSet("Deactivate", "Activate")][string]$Action,
    [string[]]$ScopeId   # optional: specific scope IDs, e.g. "192.168.1.0". Omit to target ALL scopes on this server.
)

$state = if ($Action -eq "Activate") { "Active" } else { "InActive" }

$scopes = if ($ScopeId) {
    $ScopeId | ForEach-Object { Get-DhcpServerv4Scope -ScopeId $_ }
}
else {
    Get-DhcpServerv4Scope
}

Write-Host "=== $Action DHCP scope(s) on $env:COMPUTERNAME ==="
foreach ($scope in $scopes) {
    Write-Host "Setting scope $($scope.ScopeId) ($($scope.Name)) to $state..."
    Set-DhcpServerv4Scope -ScopeId $scope.ScopeId -State $state
}

Write-Host "`n=== Current scope states on $env:COMPUTERNAME ==="
Get-DhcpServerv4Scope | Select-Object ScopeId, Name, State

if ($Action -eq "Deactivate") {
    Write-Host "`nNow run this script with -Action Activate on the NEW server, targeting the same scope IDs."
}
else {
    Write-Host "`nNew server is now live for DHCP. Watch for any client complaints over the next hour."
    Write-Host "Rollback if needed: rerun this script with -Action Deactivate here, and -Action Activate on the old server."
    Write-Host "Do NOT deauthorize/uninstall the old DHCP server yet - keep it available as a fallback for a burn-in period."
}
