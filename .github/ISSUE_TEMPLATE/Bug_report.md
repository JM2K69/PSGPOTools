---
name: Bug report
about: Create a report to help us improve

---

**Prerequisites**

Put an X between the brackets on each line to confirm you have completed them:

- [ ] The issue is still present in the latest version of the module.
- [ ] The issue has not been previously reported.

**Describe the bug**
A clear and concise description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:
1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error

**Expected behavior**
A clear and concise description of what you expected to happen.

**Screenshots or Transcripts**
If applicable, add screenshots or PowerShell transcripts to help explain your problem. You can use ```Start-Transcript``` and ```Stop-Transcript``` to record the steps you have performed.

**System Details**

- PSGPOTools version or commit:
- PowerShell version (`$PSVersionTable.PSVersion`):
- The console runs on: [Windows | Linux] and its version
- The domain controller: [Samba AD (`samba -V`) | Windows Server] and its version
- The account: [Domain Admins | a delegated account | a creator of the approval workflow]
- The whole error: `$Error[0] | Format-List * -Force`

Remove what is private (names, SIDs, addresses), and say where you did. A security issue goes
to a private security advisory, not here (see SECURITY.md).

**Additional context**
Add any other context about the problem here. Is there any other information like system configuration or data that might help us understand the problem.
