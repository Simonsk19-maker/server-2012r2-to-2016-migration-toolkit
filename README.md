# Server 2012 R2 -> 2016 Migration Runbook

Migrates AD DS (Domain Controller), DNS, DHCP, and File Server roles from
an old Windows Server 2012 R2 box to a new Windows Server 2016 box, with
very little downtime.

Confirmed installed roles on the old server (from `Get-WindowsFeature`):
**AD DS, DNS, DHCP, File Server**. (Certificate Services, Print Server,
WSUS, IIS, RDS, Hyper-V, and clustering were all checked and are NOT
installed, so they're out of scope here.) SMB1/CIFS is also currently
enabled - flagged as a separate decision, not carried forward by default.

## Why this is a staged runbook, not one script

Unlike a file/mail migration, you don't "copy" a Domain Controller with a
script. The correct, Microsoft-supported approach - and the reason this
achieves very little downtime - is to run the **old and new servers
side by side** for most of the process: promote the new server as a
*second* DC in the same domain, let normal AD replication catch it up in
the background while the old server keeps serving everyone, verify
everything matches, then move roles across in controlled steps. There is
exactly **one** step with real cutover risk (DHCP scope activation,
stage 5) - everything else either has zero downtime by design or is
reversible while the old server is still up.

**Do not skip stages or run them out of order.** Each stage assumes the
previous one is verified working, not just "probably fine."

## Hard blocker to check first

**SYSVOL must already be on DFSR, not the legacy FRS.** Server 2016
cannot be promoted into a domain still using FRS for SYSVOL replication.
`01-Preflight-Checks.ps1` checks this automatically (`dfsrmig
/getmigrationstate`) - if it's not fully migrated, stop and resolve that
first (a separate, well-documented Microsoft procedure, not part of this
toolset) before continuing with anything below.

## Stages

| # | Script | Runs on | Downtime | Notes |
|---|---|---|---|---|
| 1 | `01-Preflight-Checks.ps1` | Old server | None (read-only) | Checks SYSVOL/DFSR, dcdiag, replication health, inventories DHCP/DNS/shares |
| 2 | `02-Promote-NewDC.ps1` | New server | None | Installs AD DS + DNS, promotes as a 2nd DC. Old server keeps working throughout |
| 3 | `03-Verify-Replication.ps1` | Either | None | **STOP AND VERIFY** - don't continue until this is genuinely clean |
| 4a | `04a-Export-DHCP-OldServer.ps1` | Old server | None (read-only) | Exports scopes/reservations/leases/options |
| 4b | `04b-Import-DHCP-NewServer.ps1` | New server | None | Imports, but scopes stay inactive - not serving yet |
| 5 | `05-Cutover-DHCP-Scopes.ps1` | Both (run twice) | **~1-2 minutes, the one real cutover** | Deactivate old, then activate new. Reversible if something looks wrong |
| 6 | `06-Migrate-FileShares.ps1` | New server | None for the first pass, brief for `-FinalPass` | Run once early (full copy, no downtime), once during cutover (`-FinalPass`, fast incremental + recreates shares) |
| 7 | `07-Move-FSMORoles.ps1` | Either | None | Clean transfer, not a seize - both DCs healthy and online |
| 8 | `08-Decommission-OldDC.ps1` | Old server | None for anyone else | **Only after a 1-2 week burn-in period.** Irreversible - refuses to run without `-IReallyMeanIt` and a checklist confirmed first |

## Suggested timeline

- **Days 1-3 ahead**: Stage 1 (pre-flight), build/patch/domain-join the
  new server, Stage 2 (promote), Stage 3 (verify - check again a few
  times over a day or two as replication settles).
- **A day or two ahead**: Stage 4a/4b (DHCP export/import, not yet
  active), Stage 6 first pass (full file copy, no `-FinalPass`).
- **Cutover window** (short, ideally out of hours): Stage 5 (DHCP
  cutover), Stage 6 second pass with `-FinalPass`, Stage 7 (FSMO
  transfer). This is genuinely quick - the slow parts already happened
  ahead of time.
- **1-2 weeks later, after confirming everything's stable**: Stage 8
  (decommission the old server).

## Before starting at all

- Full backup of the old server, taken before Stage 2.
- New server built, patched, static IP assigned, joined to the domain as
  a member server with its DNS temporarily pointed at the old server.
- Know the domain name (e.g. `makelifeeasy.local`) - needed as a
  parameter for Stage 2.
- A DSRM (Directory Services Restore Mode) password will be set during
  Stage 2 - write it down somewhere safe, it's needed for AD disaster
  recovery and isn't the same as any other admin password.
