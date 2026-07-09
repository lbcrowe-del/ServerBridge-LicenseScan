# Security

## Design posture

This tool is **read-only**. It requests only read-scoped delegated Microsoft Graph
permissions (`User.Read.All`, `Organization.Read.All`, `AuditLog.Read.All`), never
writes to your tenant, and stores nothing beyond the CSV you explicitly request. It
contains no telemetry and makes no network calls other than to Microsoft Graph.

Official releases are Authenticode-signed. Verify with:

```powershell
Get-AuthenticodeSignature ./Invoke-LicenseScan.ps1 | Format-List Status
```

## Reporting a vulnerability

Please email **security@leecrowesoftware.com** with details. We aim to acknowledge
within 3 business days. Do not open a public issue for security reports.
