# Hardening

HGPM gives technicians of Tier 1 and Tier 2 the creation of GPOs, and approvers of Tier 0 the
power to make them apply. Each right a technician has is a way to make Tier 0 act for it: this
page lists what the console does not trust, what it does instead, and what was tested, by the
tests of the module (`CI/tests/PSGPOTools.Hardening.tests.ps1` and others) and on both labs
([hardenbox.labo, Samba AD and powershell.labo, Active Directory](../getting-started/lab.md)).

| What a technician controls | What HGPM does |
|---|---|
| the `gPCFileSysPath` of its GPO (it owns it while it waits) | [uses the folder of the GPO only](#redirected-gpo), refuses a redirected GPO |
| the permissions of its GPO, outside the console | the approval [rebuilds them](../workflows/approval.md#4-approve-it-tier-0) from what an approved GPO may hold |
| what is in its GPO until the approval | the approval [backs up](../workflows/approval.md#4-approve-it-tier-0) the approved version; the drift shows any change since |
| a backup on a share it can write | the [paths of the files](#other-guards) of a backup are checked |
| an older console, a domain controller without the configuration | the [configuration fails closed](#configuration-fails-closed) |

## A GPO redirected to another folder { #redirected-gpo }

### The threat

The `gPCFileSysPath` attribute of a GPO says where its folder is in SYSVOL
(`\\<domain>\SysVol\<domain>\Policies\{GUID}`): the computers read the settings of the GPO there.
While a GPO waits for its approval, its creator owns it, with full control: it can write this
attribute, outside the console (`ldapmodify`, ADSI Edit), and point it at any folder:

- the configuration of the console (`SYSVOL\<domain>\PSGPOTools`), the folder of another GPO, or
  another share of a domain controller (`C$`);
- at the approval, the approver, Tier 0, gives that folder the owner and the permissions of an
  approved GPO, with its own rights: with *Edit settings*, the groups of creators could then
  change the configuration of the console and name themselves approvers;
- once approved, the computers read the settings of the GPO from the folder of the creator, never
  approved;
- deleting the GPO, `samba-tool gpo del` and `Remove-GPO` delete the folder the attribute gives.

Up to 0.1.13, the console used the attribute as it was.

### What the console does

- **The folder of the GPO only**: the console reads and writes `SysVol` and
  `<domain>\Policies\{GUID}` of the GPO, whatever its case. A GPO whose `gPCFileSysPath` is another
  folder, share or server is *redirected*: the console neither reads, writes nor approves it, says
  so in red in the tree (*redirected to another folder*) and in its details (**Redirected**: where
  the computers read it from).
- **The deletion**: the attribute is read again, set back to the folder of the GPO, then the GPO
  is deleted: `samba-tool` and `Remove-GPO` delete its own folder, not the one of the creator.
- **After the approval**: with *Edit settings* (`Workflow.CreatorRights = EditSettings`), the groups
  of creators are denied writing `gPCFileSysPath` (`(OD;;WP;f30e3bc1-9ff0-11d1-b603-0000f80367c1;;<group>)`,
  first in the DACL). They still edit the settings: the Delegation tab shows them as *Edit
  settings*, and the deny stays when an administrator gives them another level.

A redirected GPO is deleted by an administrator of the domain, or its `gPCFileSysPath` set back to
its folder (ADSI Edit, `ldbedit`): it was not approved.

### Tested

`PSGPOTools.Hardening.tests.ps1`, *A GPO redirected to another folder*:

- the folder of the GPO is used whatever the case of the server, share, domain and GUID, with or
  without a final `\`;
- 7 redirections are refused: the configuration of the console, another GPO, `..` in the path,
  another share (`NETLOGON`), `C$` of a domain controller, another server of the domain, a quote
  that would end a command of `smbclient`;
- a redirected GPO is not approved, and is red in the tree and in its details;
- the approval with *Edit settings* adds the deny, first, kept when the level changes; not with
  *Read only*;
- the deletion sets the attribute back before `samba-tool gpo del` or `Remove-GPO`.

On both labs, with a decoy folder `SYSVOL\<domain>\HGPM-decoy` (one file):

| Step | hardenbox.labo (Samba AD) | powershell.labo (Active Directory) |
|---|---|---|
| `tiers1` creates a GPO, which waits for its approval | yes | yes |
| `tiers1` writes its `gPCFileSysPath` to the decoy (the threat) | **allowed** | **allowed** |
| The administrator reads the domain: the GPO is redirected, red in the tree | yes | yes |
| Reading its files | refused | refused |
| Approving it | refused, it stays pending | refused, it stays pending |
| Deleting it | the attribute set back, then deleted | the attribute set back, then deleted |
| The decoy after the deletion | its file and its ACL unchanged | its file and its ACL unchanged |
| A second GPO approved with *Edit settings*: the deny | on the group of creators | on the group of creators |
| The Delegation tab | the group: *Edit settings* | the group: *Edit settings* |
| `tiers1` writes its `gPCFileSysPath` | **refused** (insufficient access rights) | **refused** (insufficient access rights) |
| `tiers1` renames it (a setting it edits) | allowed | allowed |

## The configuration of the domain fails closed { #configuration-fails-closed }

### The threat

The configuration of the domain (`SYSVOL\<domain>\PSGPOTools\Configuration.psd1`) sets the
approval workflow, the roles, the central audit log and the backups of Tier 0. Without it, the
defaults apply, and the default of `Workflow.Enabled` is `$false`: no GPO waits for an approval.
The domain still delegates the creation of GPOs to the creators (`Initialize-PSGPOWorkflow`), so a
GPO they create would apply at once. Up to 0.1.13, a console fell back to the defaults when the
configuration:

- could not be read, or held a wrong value;
- held a setting it did not know: a newer console wrote it (`Audit.Tiers` came with 0.1.12), and
  the whole configuration was left out;
- was not on the domain controller it reads: Samba does not replicate SYSVOL.

An administrator who opened the console on such a domain controller created an empty
configuration there: the workflow off for every console reading it.

### What the console does

| Case | Before (0.1.13) | Now |
|---|---|---|
| A setting the console does not know | the whole configuration left out, workflow off | that setting left out with a warning, the others used; kept when the console saves the configuration |
| The configuration cannot be read, or holds a wrong value | defaults, workflow off | not used; the accounts that are not administrators of the domain create no GPO (*the approval workflow is unknown*) |
| The console is older than `Console.MinimumVersion` | (no such setting) | not used; no GPO created by those accounts, the message says to update |
| No configuration on the domain controller, the creation of GPOs delegated | defaults, workflow off | no GPO created by those accounts, the message says to copy it there |
| The same, for an administrator opening the console | an empty configuration created | not created, a warning says where it is |
| No configuration, no delegation (the workflow never deployed) | defaults | defaults |

The administrators of the domain keep working in every case: they fix the configuration. The
delegation is read in the permissions of `CN=Policies,CN=System`: the right to create
`groupPolicyContainer` objects given to a group other than Domain Admins, Enterprise Admins,
Group Policy Creator Owners, Administrators or SYSTEM.

`Console.MinimumVersion` ([reference](../reference/configuration.md#console)) is the way to stop
older consoles: set it once every console is updated. The consoles older than 0.1.14 do not know
it: they leave out the whole configuration, as before. Update them first.

### Tested

`PSGPOTools.Configuration.tests.ps1` and `PSGPOTools.Workflow.tests.ps1`:

- a configuration that needs a newer console, holds a wrong minimum version, or a table where a
  value is expected, is not used, and says why;
- the settings a newer console wrote are left out with a warning, the others used, and they are
  kept when the configuration is saved; this console does not set them;
- the creation of GPOs stops when the configuration is not used, and when it is missing while the
  domain delegates the creation of GPOs; an administrator of the domain, and a domain without the
  delegation (Group Policy Creator Owners only), are not stopped;
- no empty configuration is created on a domain controller without it when the domain delegates
  the creation of GPOs.

On both labs, the configuration of the domain saved first and restored at the end, byte for byte;
`tiers1`, a creator, after each change:

| The configuration of the domain | hardenbox.labo (Samba AD) | powershell.labo (Active Directory) |
|---|---|---|
| As it is | workflow known, its GPO created waiting for approval | workflow known, its GPO created waiting for approval |
| With `Console.MinimumVersion = '99.0'` | *the approval workflow is unknown*: no GPO created | *the approval workflow is unknown*: no GPO created |
| With a setting no console knows (`Future.Mode`) | a warning; workflow known, its GPO created waiting for approval | a warning; workflow known, its GPO created waiting for approval |
| Removed from the domain controller | *the domain delegates the creation of GPOs, but dc.hardenbox.labo has no configuration*: no GPO created | *the domain delegates the creation of GPOs, but ADDS.powershell.labo has no configuration*: no GPO created |
| The administrator opens the console then | the configuration not created, a warning | the configuration not created, a warning |
| Restored | workflow known, its GPO created waiting for approval | the same bytes, read without a warning |

## Other guards { #other-guards }

`PSGPOTools.Hardening.tests.ps1` also tests:

| Guard | Why |
|---|---|
| The paths of the files of a backup stay in the folder of the GPO (no `..`, no rooted path, no quote) | a backup comes from a share others can write: a restore would write elsewhere, a quote would end a command of `smbclient` |
| A backup of another domain is never restored on a GPO of this domain with the same GUID (the default GPOs) | the GUIDs of the default GPOs are the same in every domain |
| Wildcards in the names given to the commands, and two GPOs with the same name | each is backed up and compared, not the first one found |
| A GPO changed since it was read is not written over (`versionNumber`, `gPLink` compared in the same request) | another console, or GPMC, changed it meanwhile |
| The approval writes SYSVOL, then the containers the GPO holds, then the GPO; a failure leaves it pending | its owner is what makes it approved: never approved with a folder its creator still owns |
| The permissions added while a GPO was pending are removed at the approval, and listed | the creator owned it, and could add any ACE |
| SYSVOL with `-Credential` on Windows: the share reached once with that account | the session of another account is never used by mistake |
| Reading a large domain: 2 000 GPOs and 1 000 OUs in a few seconds | the console stays usable on a large domain |

Run them:

```powershell
pwsh -Command "& ./CI/Invoke-Tests.ps1 -Path CI/tests/PSGPOTools.Hardening.tests.ps1"
```

## Known limits

These were found by the same review, and are not fixed yet:

- while an approver reviews a GPO, its creator can still change it: the approval approves what the
  GPO holds then, which the approved backup records, and which may differ from what was reviewed;
- an account in both `Workflow.Creators` and `Workflow.Approvers` is an approver: its GPOs do not
  wait for an approval. Keep the groups apart;
- the owner of a file of the central audit log can rewrite it: the log of the system (SIEM) keeps a
  copy of each change.
