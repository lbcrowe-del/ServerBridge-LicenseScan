# Privacy

**ServerBridge License Scan (free community edition)**

This tool is designed to touch as little as possible and keep nothing. Here is
exactly what it does and does not do with your data.

## What it accesses (read-only)

When you sign in, the tool requests these **delegated, read-only** Microsoft Graph
scopes and nothing more:

| Scope | Why |
|-------|-----|
| `User.Read.All` | List licensed users and whether each account is enabled |
| `Organization.Read.All` | Read your tenant name and subscribed licenses (SKUs) |
| `AuditLog.Read.All` | Read last sign-in activity (Entra ID P1 tenants) |
| `Reports.Read.All` | Read Microsoft 365 usage activity (fallback for non-P1 tenants) |

It reads license assignments and last-activity dates to identify unused seats.
It does **not** read message content, files, mailboxes, or any personal content.

## What it does NOT do

- **No writes.** It never assigns, removes, or changes licenses, users, or any
  setting in your tenant. Every call is a read.
- **No storage of your data by us.** The tool sends nothing to Lee Crowe Software
  Solutions or any third party. There is no telemetry, no analytics, no "phone home."
- **No credentials stored.** Sign-in uses device-code flow under *your* identity via
  Microsoft's own login. The tool never sees or stores your password, and the access
  token lives only in memory for the duration of the run.

## Where your data goes

Data flows only between **your machine** and **Microsoft Graph**. The single output
is the CSV file you choose to write locally (default: your current folder). That file
stays on your machine; do with it as you wish. Delete it when you're done if you like.

## Verifying this yourself

The tool is a single, open-source PowerShell script (MIT licensed). Read it before
you run it, and confirm the requested scopes on Microsoft's consent screen at sign-in.
Official releases are Authenticode-signed by Lee Crowe Software Solutions LLC.

## The paid product

The paid [ServerBridge License Auditor](https://server-bridge.com/license-auditor.html)
is a separate product with its own terms and privacy policy; this document covers the
free community script only.

## Contact

Questions about data handling: **privacy@leecrowesoftware.com**
