# File formats

## The folder of a GPO

```text
{GUID}/
  GPT.INI                                      [General] Version=<user << 16 | computer>
  Machine/
    Registry.pol                               administrative templates of the computer
    Microsoft/Windows NT/SecEdit/GptTmpl.inf   security settings
    Preferences/<Type>/<Type>.xml              Group Policy Preferences
    Scripts/...
  User/
    Registry.pol
    Preferences/<Type>/<Type>.xml
```

## Registry.pol

`GPOToolsRegistryPol`, [MS-GPREG] 2.1: the signature `PReg`, version 1, then entries
`[key;value;type;size;data]` in UTF-16LE, the brackets and semicolons as UTF-16 characters. The
console reads and writes it byte for byte: a file read and written again is the same file.

| Value name | Meaning |
|---|---|
| a name | sets the value |
| `**del.<name>` | deletes the value |
| `**delvals.` | deletes every value of the key, before the others |
| `**DeleteValues` / `**DeleteKeys` | delete the values / subkeys listed in the data |

The state of a policy comes from its ADMX: its `enabledValue` / `disabledValue`, the values of its
elements, the deletes it writes when it is disabled. A policy whose values are all there is enabled,
one whose disabled values are there is disabled; what no policy explains is an extra registry
value.

## GptTmpl.inf

`GPOToolsSecurityTemplate`: an INF file in UTF-16LE with a byte order mark, `[Unicode]
Unicode=yes` and `[Version] signature="$CHICAGO$"`, then its sections (`[System Access]`,
`[Kerberos Policy]`, `[Event Audit]`, `[Privilege Rights]`, `[Registry Values]`, the event logs).
`[Registry Values]` holds `MACHINE\...\Name=<type>,<data>`; `[Privilege Rights]` lists accounts as
`*SID`. A file written by `samba-tool gpo manage security` (without `[Unicode]` nor `[Version]`)
is read too.

## scripts.ini and psscripts.ini

`GPOToolsScriptsFile` ([MS-GPSCR] 2.2.2): `Machine\Scripts\scripts.ini` (startup, shutdown) and
`User\Scripts\scripts.ini` (logon, logoff), `psscripts.ini` beside them for the Windows PowerShell
scripts; INI files in UTF-16LE with a byte order mark, an empty line first, as the Group Policy
editor writes them:

```ini
[Startup]
0CmdLine=Install-Agent.cmd
0Parameters=/quiet
```

A script is `<n>CmdLine` and `<n>Parameters`, numbered from 0 in the order it runs; a command line
without a root is a file of `Machine\Scripts\Startup` (`Shutdown`, `User\Scripts\Logon`,
`Logoff`). `[ScriptsConfig]` of `psscripts.ini` says whether the PowerShell scripts run first:
`StartExecutePSFirst` (startup, logon), `EndExecutePSFirst` (shutdown, logoff), `true` or `false`.
The other sections and keys are kept. The extension of the scripts is
`{42B5FAAE-6536-11D2-AE5A-0000F87571E3}`, with the tool `{40B6664F-4972-11D1-A7CA-0000F87571E3}`
for the computer and `{40B66650-4972-11D1-A7CA-0000F87571E3}` for the user.

## The report of a GPO

`Get-PSGPOReport -ReportType Xml` writes an XML document of HGPM, in English (not the schema of the
reports of GPMC), in the namespace `https://jm2k69.github.io/PSGPOTools/schemas/gpo-report/1`:

```xml
<GpoReports generated="..." generatedBy="HGPM 0.1.16-alpha">
  <Gpo id="{...}" name="T1 - Servers - Proxy" domain="contoso.com">
    <Details owner="..." status="Enabled" approval="Pending" computerVersion="3" userVersion="0"/>
    <Links><Link name="Servers" container="OU=Servers,..." enabled="true" enforced="false" order="1"/></Links>
    <SecurityFiltering><Trustee>Authenticated Users</Trustee></SecurityFiltering>
    <Permissions><Permission trustee="..." permission="GpoEdit" inherited="false" denied="false"/></Permissions>
    <Extensions><Extension scope="Machine" guid="{...}" name="Scripts" interpreted="true"/></Extensions>
    <Computer><Setting path="Policies > ..." name="..." state="...">options</Setting></Computer>
    <User/>
    <NotInterpreted><Setting path="Client-side extensions" name="Folder Redirection" state="User">...</Setting></NotInterpreted>
  </Gpo>
</GpoReports>
```

`-ReportType Html` writes a page in one file, in the language of the interface, readable in any
browser; `-ReportType Object` gives `PSGPOTools.GpoReport` objects with the same parts.

## Group Policy Preferences

`GPOToolsPreferenceFile`: the XML of a preference type, read and written with `System.Xml`.
`Resources/Preferences.json` describes the 21 types ([MS-GPPREF] 1.9, 2.2.1): their file, the
client-side extension and its tool, the elements and their CLSIDs, the attributes of their
`Properties` and their kinds.

```xml
<RegistrySettings clsid="{A3CCFC41-DFDB-43a5-8D26-0FE8B954DA51}">
  <Registry clsid="{9CD4B2F4-923D-47f5-A062-E897DD1DAD50}" name="Baseline" status="Baseline"
            image="7" changed="2026-10-15 08:45:12" uid="{...}" desc="Version of the Tier 1 baseline"
            bypassErrors="1">
    <Properties action="U" hive="HKEY_LOCAL_MACHINE" key="SOFTWARE\HardenBox\Tier1" name="Baseline" type="REG_SZ" value="2026.10"/>
  </Registry>
</RegistrySettings>
```

## Backups

```text
<root>/<GPO name> {<GUID>}/<yyyy-MM-dd_HH-mm-ss>/manifest.json
```

```json
{
  "Format": "PSGPOTools.Backup/1",
  "BackedUp": "2026-10-16T09:47:04.0000000Z",
  "Domain": "hardenbox.labo",
  "Server": "dc.hardenbox.labo",
  "Account": "HARDENBOX\\Administrator",
  "Gpo": {
    "Id": "f1726771-92f6-4598-9775-a26d8b33a1c8",
    "DistinguishedName": "CN={F1726771-...},CN=Policies,CN=System,DC=hardenbox,DC=labo",
    "FileSysPath": "\\\\hardenbox.labo\\SysVol\\hardenbox.labo\\Policies\\{F1726771-...}",
    "Modified": "2026-10-16T09:46:58.0000000Z",
    "DisplayName": "T1 - Workflow test",
    "Version": 65537, "ComputerVersion": 1, "UserVersion": 1,
    "Flags": 0, "Status": "Enabled",
    "SecurityFiltering": ["Authenticated Users"], "DeniedTo": [],
    "MachineExtensionNames": "[{35378EAC-...}{D02B1F72-...}]", "UserExtensionNames": null,
    "Links": [{ "Container": "OU=Tier 1,DC=hardenbox,DC=labo", "Enabled": true, "Enforced": false, "Order": 1 }]
  },
  "Files": [{ "Path": "Machine\\Registry.pol", "Size": 98, "Sha256": "..." }]
}
```

`notes.json`, beside it, when the backup has notes:

```json
{
  "Format": "PSGPOTools.BackupNotes/1",
  "Comment": "Approved by HARDENBOX\\Administrator, created by TIERS1: the creators read it; applied by Authenticated Users.",
  "Labels": ["Approved"],
  "Updated": "2026-10-16T09:47:05.0000000Z",
  "UpdatedBy": "HARDENBOX\\Administrator",
  "RestoredAs": null
}
```

`RestoredAs` is the GUID of the GPO created again from this backup of a deleted GPO: it takes the
deleted one out of the recycle bin.

## The configuration of the domain

A PowerShell data file (`.psd1`) with the keys it changes, read with `Import-PowerShellDataFile`
([configuration reference](../reference/configuration.md)).
