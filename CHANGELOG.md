# Changelog

## Unreleased

### Fixed
- **Sign-in was impossible on Microsoft Graph PowerShell SDK 2.38.** Both commands printed "a device
  code will appear below", then no code, then timed out after two minutes. `Connect-MgGraph
  -UseDeviceCode` writes the code to PowerShell's *success* stream, and both commands called the
  sign-in helper in a way that captured that stream — so the code ended up in a return value instead
  of on your screen. If you hit this, nothing was wrong on your side and nothing you could change
  would have helped.

### Added
- **`Invoke-OffboardingCheck -UseExchangeOnline` (experimental).** Reads mailbox types from Exchange
  Online instead of Microsoft's usage report. Off by default, because it costs a second sign-in and
  needs `ExchangeOnlineManagement` installed. Read-only, and it falls back to the usage report if it
  can't connect.

### Fixed
- **"Mailbox not shared: 0" when no mailbox type could be read.** That zero looked like an all-clear
  on something nobody had checked. It now reads `unknown`, or shows the count of unreadable ones
  alongside the real figure.

### Notes
- Why the Exchange option exists: Microsoft's `getMailboxUsageDetail` only lists mailboxes that have
  had **activity**. A shared mailbox nobody has touched is missing from it entirely — confirmed on a
  live tenant on 2026-09-22 against a mailbox Exchange had reported as `SharedMailbox` for a week,
  at both the 7-day and 180-day windows. That is the mailbox most likely to be wasting a licence, so
  the report is blind in exactly the place it matters most.

## 1.2.1 — 2026-09-17

### Fixed
- **Mobile-only users were reported as dormant.** Both commands read only Microsoft's *interactive*
  sign-in timestamp. People who live in Outlook or Teams on a phone often have no interactive
  sign-in at all, because those clients sign in on the user's behalf — so an active person could be
  listed as a licence worth removing. That is the worst mistake this tool can make, and it's fixed:
  the scan now takes the most recent of Microsoft's three timestamps
  (`lastSuccessfulSignInDateTime`, `lastSignInDateTime`, `lastNonInteractiveSignInDateTime`).
  Reported by **robofski** on r/PowerShell.

### Notes
- The new reading deliberately errs toward "active". Under-flagging costs you a missed saving;
  over-flagging tells you to remove a licence from someone still working.
- `lastSuccessfulSignInDateTime` is the best signal — it means the account was genuinely accessed —
  but Microsoft only began populating it in December 2023 and never backfilled it, so older tenants
  fall back to the other two.
- Tenants without Entra ID P1 were never affected: the usage-report fallback measures service
  activity, not sign-ins.

## 1.2.0 — 2026-09-16

### Added
- **New command: `Invoke-OffboardingCheck`.** Finds accounts that look like leavers — disabled, or no
  activity for `-InactiveDays` — and shows what each one still holds: paid licenses, how many groups
  and directory roles it still belongs to, and whether its mailbox was never converted to shared.
  One row per person, not per license, plus a CSV. Read-only, like everything else here.
- Mailbox type comes from Microsoft's mailbox usage report, so no Exchange Online PowerShell is
  needed and no extra permission is requested — it uses the same `Reports.Read.All` the license scan
  already asks for.

### Changed
- The module now exports two commands. Both share one copy of the device-code sign-in (including the
  2-minute retry added in 1.1.1), the Entra P1 → usage-report fallback, the concealed-names help and
  the CSV escaping, so the two checks can't drift apart.

### Notes
- Where the offboarding check can't know something, it says so instead of guessing: an unreadable
  group count stays blank rather than showing `0`, and mailbox type reads `unknown` when the report
  lags or your tenant conceals user names.

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
