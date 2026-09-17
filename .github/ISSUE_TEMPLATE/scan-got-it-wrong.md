---
name: The scan got something wrong
about: A number looks wrong, an account was judged wrong, or something was confusing
title: ''
labels: ''
assignees: ''
---

Thanks for taking the time. Don't worry about filling in every box — even a one-line
"this bit was confusing" is useful.

**Which command?**
`Invoke-LicenseScan` / `Invoke-OffboardingCheck`

**What did it say, and what's actually true?**
<!-- Redact user names and your tenant name freely - a UPN like user1@example.com is fine. -->

**Does your tenant have Entra ID P1 or P2?**
<!-- This decides whether the scan used sign-in activity or fell back to Microsoft 365 usage
     reports, and the two behave differently. If you're not sure, say "not sure". -->

**Anything in the output above the totals?**
<!-- e.g. "Sign-in activity needs Entra ID P1...", "PARTIAL AUDIT", or a message about hidden
     user names in reports. These usually explain the result. -->

**Version and PowerShell**
<!-- `Get-InstalledModule ServerBridge.LicenseScan | Select Version` and `$PSVersionTable.PSVersion` -->

---

Nothing here is required. If it's easier to just describe what happened in a sentence, do that.
