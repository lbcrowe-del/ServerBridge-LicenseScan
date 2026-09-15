# Changelog

## 1.1.1 — 2026-09-15

### Fixed
- **Sign-in code expiring.** Microsoft's Graph PowerShell module only waits 2 minutes for the device
  code, and that limit can't be changed. The scan now tells you before the code appears, and if it
  expires it offers a new code in the same window (press Enter) instead of stopping.

## 1.1.0 — 2026-09-14

**Now on the PowerShell Gallery.** Install with `Install-Module ServerBridge.LicenseScan -Scope CurrentUser`
and run `Invoke-LicenseScan`. The standalone `Invoke-LicenseScan.ps1` download still works.

### Added
- PowerShell Gallery module `ServerBridge.LicenseScan`. `Install-Module` brings the Microsoft Graph
  modules it needs along with it.
- Works on **Windows PowerShell 5.1** as well as PowerShell 7+.
- **Hidden user names in usage reports.** On tenants without Entra ID P1, when Microsoft hides user
  names in its reports (the default), the scan stops before giving you a misleading total. It shows
  the one-minute fix and checks again when you press Enter, without a new sign-in. If you skip it, the
  result is labeled **PARTIAL AUDIT**.
- Shows the tenant and the signed-in account before scanning.
- Module files are signed, as well as the script.

### Fixed
- Crash on tenants with no licensed users ("Cannot bind argument to parameter 'Users' because it is
  null").
- The per-license table showed three decimal places in the Annual $ column. It now shows whole dollars.

### Security
- The CSV is safe to open in Excel. Any cell starting with `=`, `+`, `-` or `@` is stored as plain
  text, so a crafted display name (for example, a guest's) can't run as a formula.
- The Microsoft sign-in is kept in memory for the run only. Earlier versions left it cached on disk
  and could quietly reuse an earlier sign-in.

## 1.0.0 — 2026-07-09

First release: a signed, read-only PowerShell script that prices dormant Microsoft 365 licenses,
using sign-in activity or Microsoft 365 usage reports, with CSV export.
