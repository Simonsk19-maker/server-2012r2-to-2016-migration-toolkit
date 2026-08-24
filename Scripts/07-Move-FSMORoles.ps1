<#
  07-Move-FSMORoles.ps1
  RUN ON: either server (targets the new server by name).
  RUN WHEN: after replication (stage 3), DHCP cutover (stage 5), and file
  shares (stage 6) are all done and stable - this is one of the last
  steps before the old DC can be considered for decommissioning.

  Moves all 5 FSMO roles from wherever they currently sit to the new
  server: Schema Master, Domain Naming Master, RID Master, PDC Emulator,
  Infrastructure Master. This is a clean TRANSFER (both DCs are healthy
  and online) - not a SEIZE, which is only for when the old DC has
  already failed/is unreachable and is a much more disruptive last resort.
#>

param(
    [Parameter(Mandatory)][string]$NewDCName
)

Write-Host "=== FSMO roles BEFORE ==="
netdom query fsmo

Write-Host "`n=== Transferring all 5 FSMO roles to $NewDCName ==="
Move-ADDirectoryServerOperationMasterRole -Identity $NewDCName -OperationMasterRole `
    SchemaMaster, DomainNamingMaster, PDCEmulator, RIDMaster, InfrastructureMaster -Confirm:$false

Write-Host "`n=== FSMO roles AFTER (all 5 should now show $NewDCName) ==="
netdom query fsmo
