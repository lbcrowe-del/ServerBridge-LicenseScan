# Microsoft 365 Unused License Scan

**Find the Microsoft 365 licenses nobody's using — and see the spend you can recover.**
A free, **read-only** PowerShell script that cross-checks every assigned license against
real sign-in activity and tells you, in dollars, which seats are dead weight.

No app registration. No agent. Nothing stored. It never changes anything in your tenant.

> The free community scan. For the formatted PDF report, per-SKU downgrade recommendations,
> scheduled re-audits and support, see the **[ServerBridge License Auditor](https://server-bridge.com/license-auditor.html)**.

## What it does

1. Reads your subscribed SKUs and who they're assigned to (Microsoft Graph).
2. Cross-checks each licensed user against their **last sign-in**.
3. Flags users dormant past a threshold (default **90 days**) and prices the wasted seats.
4. Prints a summary and exports a per-user CSV.

```
Wasted spend by license (dormant 90+ days)
-----------------------------------------------------
License            DormantSeats   Annual $
--------           ------------   --------
ENTERPRISEPACK               12      5,184
SPE_E5                        3      2,052
POWER_BI_PRO                  6        720

  Reclaimable seats : 21
  Wasted spend      : $7,956 / year
```

## Requirements

- **PowerShell 7+** (Windows, macOS or Linux)
- **Microsoft Graph PowerShell SDK**
  ```powershell
  Install-Module Microsoft.Graph -Scope CurrentUser
  ```
- Permission to consent to four **read-only** delegated scopes:
  `User.Read.All`, `Organization.Read.All`, `AuditLog.Read.All`, `Reports.Read.All`
  (Global Reader is enough).

> **No Entra ID P1?** No problem. Sign-in activity needs Entra ID P1, so on tenants
> without it the scan automatically falls back to the Microsoft 365 usage reports for
> last-activity data, and always flags disabled-but-licensed accounts.

## Quick start

```powershell
# 1. Get the script (use a signed release asset — see "Verifying" below)
# 2. Run it. A device code appears; sign in and consent.
./Invoke-LicenseScan.ps1

# Options
./Invoke-LicenseScan.ps1 -InactiveDays 60          # tighter dormancy window
./Invoke-LicenseScan.ps1 -IncludeGuests            # also score guest accounts
./Invoke-LicenseScan.ps1 -OutputCsv C:\reports\waste.csv
```

Prices are public **list-price estimates** (USD/user/month) so you get a dollar figure out of
the box. Edit the price table near the top of the script to match your actual contract.

## Privacy & safety

- **Read-only.** Requests only read scopes; it never unassigns, edits or deletes.
- **Nothing leaves your machine.** No telemetry, no upload. The only output is the CSV you asked for.
- **Inspect it.** It's a single, readable script — read it before you run it.

## Verifying the signature

Official releases are **Authenticode-signed** by Lee Crowe Software Solutions LLC via Azure
Trusted Signing (the same publicly-trusted certificate profile used for the ServerBridge app).
Verify before running:

```powershell
Get-AuthenticodeSignature ./Invoke-LicenseScan.ps1 | Format-List Status, SignerCertificate
# Status should be 'Valid'
```

## When you outgrow the free scan

The free scan tells you *what's* wrong. The paid **[ServerBridge License Auditor](https://server-bridge.com/license-auditor.html)**
fixes it and keeps it fixed — boardroom-ready PDF, downgrade recommendations by SKU, scheduled
re-audits with drift tracking, guest/shared-license flags, multi-tenant roll-up, and support.

## License

[MIT](LICENSE) © Lee Crowe Software Solutions LLC
