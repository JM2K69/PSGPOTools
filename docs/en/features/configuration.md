# Configuration of the domain

The configuration of PSGPOTools is **the one of the domain**, the same for every console of the
domain:

```text
\\<domain controller>\SYSVOL\<domain>\PSGPOTools\Configuration.psd1
```

- Only the **administrators of the domain** can write it: SYSVOL lets Authenticated Users read
  it and the administrators write it, so a technician cannot give itself another configuration.
- There is **no configuration of the user**, and no local file says where it is: the console reads
  it from the domain controller it reads the domain from.
- It holds only the settings it changes; the others keep the default of the module
  (`Resources/Configuration.psd1`, every setting commented).
- It is read as data (`Import-PowerShellDataFile`), never run. A file that cannot be read or holds
  a wrong value is reported, and the defaults apply.

```powershell
@{
    NewGpo = @{
        Status = 'ComputerOnly'
        SecurityFilteringGroups = @{ Create = $true; Container = 'OU=GPO,OU=Groups' }
    }
    Workflow = @{ Enabled = $true; Creators = 'GPO-Tier1-Admins, GPO-Tier2-Admins' }
}
```

Every setting is described in [the configuration reference](../reference/configuration.md).

## The Settings window

**Settings** in the toolbar lists every setting with its value, its default and where the value
comes from. Choose a setting, give its value, **Set the value**, or **Remove** it to use its
default; **Save** writes the file, refused to an account that is not an administrator of the
domain. A value is checked with the others before it is kept.

![The Settings window](../assets/screenshots/09-configuration-window.png)

A directory that cannot be written (the demonstration environment) shows its configuration
without saving it.

## When it is read

With the domain (`Get-PSGPODirectory`), when the window or the Settings window opens, and by each
command given a directory. `Get-PSGPOConfiguration` shows where it comes from:

```powershell
Get-PSGPOConfiguration -Server dc.hardenbox.labo | Format-List DefaultPath, Domain, DomainPath, DomainFileExists, Problem
```
