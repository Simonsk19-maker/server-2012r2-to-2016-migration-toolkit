# Pre-Flight Checks Explained

What `Scripts\01-Preflight-Checks.ps1` actually checks, why each one
matters, and what a bad result means. Run this script on the old server
first and read its output against this before doing anything else.

## 1. SYSVOL replication mode (SYSVOL/DFSR vs FRS) — the hard blocker

Old Windows domains replicated the SYSVOL folder (Group Policy files,
logon scripts) using a service called **FRS** (File Replication
Service). Microsoft replaced it years ago with **DFSR** (Distributed
File System Replication), which is faster and more reliable — but a lot
of domains that have been upgraded in place over the years (2003 → 2008
→ 2012 → 2012 R2, say) never got explicitly migrated off FRS, because
Windows never forces it.

**Windows Server 2016 refuses to be promoted as a Domain Controller into
a domain that's still using FRS for SYSVOL.** This is checked with
`dfsrmig /getmigrationstate`, which reports one of four states:

| State | Meaning |
|---|---|
| Start | Still on FRS — not migrated at all |
| Prepared | Migration started, not finished |
| Redirected | Further along, still not finished |
| **Eliminated** | Fully migrated to DFSR — this is what you need to see |

If it doesn't say **Eliminated**, stop here. Migrating SYSVOL from FRS to
DFSR is its own well-documented Microsoft procedure (`dfsrmig
/setglobalstate <n>` through each stage, checking health at each step) —
it's not part of this toolset because it should be done and left to
settle *before* a server migration is even scheduled, not rushed
alongside one.

## 2. Forest and domain functional level

Checked via `Get-ADForest` / `Get-ADDomain`. Server 2016 domain
controllers need at least a Windows Server 2003 forest functional level
to join — in practice almost every real-world domain clears this easily,
but it costs nothing to confirm rather than assume.

## 3. `dcdiag /v` — overall Domain Controller health

Runs Microsoft's own built-in DC diagnostic tool: checks connectivity,
replication, advertising (is this DC properly advertising itself as a DC
and Global Catalog), Netlogon, services, and more. Look for the word
**"failed"** in the output — a healthy DC should show none. Anything
that fails here should be resolved *before* introducing a second DC,
since replication problems are much harder to diagnose once there are
two DCs to compare instead of one baseline.

## 4. `repadmin /replsummary` — replication health

Summarises replication status and USN (Update Sequence Number) deltas
between DCs. On a single-DC domain this will be simple/clean by
definition; it becomes more meaningful once the new DC is added
(stage 3's job) — running it now just confirms the starting baseline is
healthy.

## 5. Current FSMO role holders

Lists which server currently holds each of the 5 FSMO roles (Schema
Master, Domain Naming Master, RID Master, PDC Emulator, Infrastructure
Master) via `netdom query fsmo`. On a single-DC domain, that's this one
server holding all 5 — recorded now so there's a clear "before" to
compare against after stage 7 transfers them.

## 6. DHCP scope inventory

Captures every scope's ID, name, IP range, subnet mask, and state to
`Logs\dhcp-scopes-before.csv`. This is the "known good" list to check the
new server's imported scopes against in stage 4b, and to confirm nothing
was missed after the real export/import in stage 4a.

## 7. DNS zone inventory

Captures every zone and whether it's **AD-integrated**
(`Logs\dns-zones-before.csv`). This distinction matters a lot:

- **AD-integrated zones** replicate automatically to the new DC once
  it's promoted (stage 2) — no separate action needed for these.
- **Non-AD-integrated zones** (standalone primary/secondary) do **not**
  replicate automatically and need an explicit export/import
  (`Export-DnsServerZone` / `dnscmd /zoneexport` then recreate on the new
  server) — the script flags these specifically as a WARN so they don't
  get missed.

## 8. File share inventory

Captures every real share (excluding admin shares like `C$` and the
built-in `SYSVOL`/`NETLOGON`), its path, and its share-level permissions
to `Logs\file-shares-before.csv`. Two separate permission layers exist on
any shared folder — **NTFS permissions** (travel automatically with the
data when copied via `robocopy /SEC` in stage 6) and **share-level
permissions** (do not travel with the data — have to be read from the
old server and explicitly recreated on the new one, which is why this
inventory captures them now).

## 9. SMB1/CIFS flag

If installed, this is flagged as a decision point, not auto-carried
forward. SMB1 is an old, insecure protocol Microsoft has been trying to
retire for years — it's occasionally still needed by old scanners, NAS
boxes, or line-of-business devices that were never updated. Worth
actually checking what (if anything) still uses it before deciding
whether the new server needs it enabled at all.

## What "clean" looks like before moving to stage 2

- SYSVOL state: **Eliminated**
- `dcdiag`: no "failed" lines
- Forest/domain functional level: confirmed, no errors querying it
- DHCP/DNS/share inventories: saved, spot-checked that the counts look
  right (matches what's actually expected on this server)
- SMB1 decision made (even if the decision is "yes, still needed, keep
  it" — as long as it's a decision, not an oversight)
